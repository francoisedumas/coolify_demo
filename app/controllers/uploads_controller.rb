class UploadsController < ApplicationController
  http_basic_authenticate_with name: Rails.application.credentials.upload_username || ENV["UPLOAD_USERNAME"],
                                password: Rails.application.credentials.upload_lemot || ENV["UPLOAD_LEMOT"],
                                except: [:result]

  # Disable CSRF for the result endpoint (called by N8N)
  skip_before_action :verify_authenticity_token, only: [:result]

  def new
    # Renders the upload form
  end

  def create
    if params[:pdf_file].present?
      session[:processing_filename] = params[:pdf_file].original_filename

      # Fire-and-forget HTTP request (safe)
      send_to_n8n(params[:pdf_file])

      redirect_to uploads_processing_path
    else
      flash[:alert] = "Please select a PDF file"
      render :new
    end
  end

  def processing
    @filename = session[:processing_filename] || "your file"
  end

  def result
    @ocr_data = params[:ocr_result] || params

    Turbo::StreamsChannel.broadcast_replace_to(
      'ocr_channel',
      target: 'ocr_result_content',
      partial: 'uploads/ocr_result',
      locals: {ocr_data: @ocr_data}
    )
  end


  private

  def send_to_n8n(file)
    require 'net/http'
    require 'uri'

    n8n_webhook_url = Rails.application.credentials.n8n_webhook_url || ENV["N8N_WEBHOOK_URL"]
    uri = URI.parse(n8n_webhook_url)

    request = Net::HTTP::Post.new(uri)

    # Add callback URL so N8N knows where to send results
    callback_url = "#{request_base_url}/uploads/result"

    form_data = [
      ['pdf_file', file.read, { filename: file.original_filename, content_type: 'application/pdf' }],
      ['callback_url', callback_url]
    ]
    request.set_form form_data, 'multipart/form-data'

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    if http.use_ssl?
      if Rails.env.development?
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end
    end

    response = http.request(request)

    Rails.logger.info "N8N Response Code: #{response.code}"
    Rails.logger.info "N8N Response Body: #{response.body}"

    response
  rescue StandardError => e
    Rails.logger.error "Error sending to N8N: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def request_base_url
    "#{request.protocol}#{request.host_with_port}"
  end
end
