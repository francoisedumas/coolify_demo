class UploadsController < ApplicationController
  http_basic_authenticate_with name: Rails.application.credentials.upload_username,
                                password: Rails.application.credentials.upload_password

  def new
    # Renders the upload form
  end

def create
    if params[:pdf_file].present?
      # Send to N8N webhook
      response = send_to_n8n(params[:pdf_file])

      if response.is_a?(Net::HTTPSuccess)
        flash[:notice] = "File uploaded successfully!"
        redirect_to root_path
      else
        flash[:alert] = "Upload failed (HTTP #{response.code}): #{response.body}"
        render :new
      end
    else
      flash[:alert] = "Please select a PDF file"
      render :new
    end
  end

  private

  def send_to_n8n(file)
    require 'net/http'
    require 'uri'

    uri = URI.parse(Rails.application.credentials.n8n_webhook_url)

    request = Net::HTTP::Post.new(uri)
    form_data = [['pdf_file', file.read, { filename: file.original_filename, content_type: 'application/pdf' }]]
    request.set_form form_data, 'multipart/form-data'

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    if http.use_ssl?
      # In development, skip SSL verification for convenience
      # In production, verify certificates properly
      if Rails.env.development?
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end
    end

    response = http.request(request)

    # Log the response for debugging
    Rails.logger.info "N8N Response Code: #{response.code}"
    Rails.logger.info "N8N Response Body: #{response.body}"

    response
  rescue StandardError => e
    Rails.logger.error "Error sending to N8N: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
