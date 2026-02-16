require "open-uri"
TEST_IMAGE = URI.open("https://picsum.photos/id/237/536/354").read

# --- ACTIVE RECORD ---

check "We have an active database connection" do
  make_sure ActiveRecord::Base.connection.connect!.active?
end

check "The database can perform a simple query" do
  make_sure ActiveRecord::Base.connection.execute("SELECT 1 LIMIT 1").any?
end

check "The database can perform writes" do
  table_name = "allgood_health_check_#{Time.now.to_i}"
  random_id = rand(1..999999)

  result = ActiveRecord::Base.connection.execute(<<~SQL)
    DROP TABLE IF EXISTS #{table_name};
    CREATE TEMPORARY TABLE #{table_name} (id integer);
    INSERT INTO #{table_name} (id) VALUES (#{random_id});
    SELECT id FROM #{table_name} LIMIT 1;
  SQL

  ActiveRecord::Base.connection.execute("DROP TABLE #{table_name}")

  make_sure result.present? && result.first["id"] == random_id, "Able to write to temporary table"
end

check "The database connection pool is healthy" do
  pool = ActiveRecord::Base.connection_pool

  used_connections = pool.connections.count
  max_connections = pool.size
  usage_percentage = (used_connections.to_f / max_connections * 100).round

  make_sure usage_percentage < 90, "Pool usage at #{usage_percentage}% (#{used_connections}/#{max_connections})"
end

check "Database migrations are up to date" do
  make_sure ActiveRecord::Migration.check_all_pending! == nil
end

# --- ACTION CABLE ---

check "ActionCable is configured and running" do
  make_sure ActionCable.server.present?, "ActionCable server should be running"
end

check "ActionCable is configured to accept connections with a valid adapter" do
  make_sure ActionCable.server.config.allow_same_origin_as_host, "ActionCable server should be configured to accept connections"

  adapter = ActionCable.server.config.cable["adapter"]

  if Rails.env.production?
    make_sure adapter.in?([ "solid_cable", "redis" ]), "ActionCable running #{adapter} adapter in #{Rails.env}"
  else
    make_sure adapter.in?([ "solid_cable", "async" ]), "ActionCable running #{adapter} adapter in #{Rails.env}"
  end
end

check "ActionCable can broadcast messages and store them in SolidCable" do
  test_message = "allgood_test_#{Time.now.to_i}"

  begin
    ActionCable.server.broadcast("allgood_test_channel", { message: test_message })

    # Verify message was stored in SolidCable
    message = SolidCable::Message.where(channel: "allgood_test_channel")
                                .order(created_at: :desc)
                                .first

    make_sure message.present?, "Message should be stored in SolidCable"
    make_sure message.payload.include?(test_message) && message.destroy, "Message payload should contain our test message"
  rescue => e
    make_sure false, "Failed to broadcast/verify message: #{e.message}"
  end
end

# --- SYSTEM ---

check "Disk space usage is below 90%", only: :production do
  usage = `df -h / | tail -1 | awk '{print $5}' | sed 's/%//'`.to_i
  expect(usage).to_be_less_than(90)
end

check "Memory usage is below 90%", only: :production do
  usage = `free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1`.to_i
  expect(usage).to_be_less_than(90)
end
