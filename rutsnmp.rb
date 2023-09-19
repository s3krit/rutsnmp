# frozen_string_literal: true

require 'netsnmp'
require 'influxdb-client'
require 'dotenv/load'

# OIDs we care about
oids = {
  mSignal: '1.3.6.1.4.1.48690.2.2.1.12.1',
  mConnectionType: '1.3.6.1.4.1.48690.2.2.1.16.1',
  mSent: '1.3.6.1.4.1.48690.2.2.1.22.1',
  mReceived: '1.3.6.1.4.1.48690.2.2.1.23.1'
}

manager = NETSNMP::Client.new(
  host: '192.168.1.1',
  port: 161,
  version: '1',
  community: 'public'
)

oids.each do |key, oid|
  out = manager.get(oid: oid)
  puts "#{key}: #{out}"
end

token = ENV['INFLUX_TOKEN']
org = ENV['INFLUX_ORG']
bucket = ENV['INFLUX_BUCKET']
url = ENV['INFLUX_URL']

client = InfluxDB2::Client.new url, token, bucket: bucket, org: org, precision: 'InfluxDB2::WritePrecision::NANOSECOND'

loop do
  point = InfluxDB2::Point.new(name: 'rutsnmp')
  point.add_tag('host', 'rutsnmp')
  point.add_field 'mSignal', manager.get(oid: oids[:mSignal])
  point.add_field 'mConnectionType', manager.get(oid: oids[:mConnectionType])
  point.add_field('mSent', manager.get(oid: oids[:mSent]) & 0xFFFFFFFF)
  point.add_field('mReceived', manager.get(oid: oids[:mReceived]) & 0xFFFFFFFF)
  puts '---------------------'
  puts point.to_line_protocol
  puts '---------------------'

  begin
  write_options = InfluxDB2::WriteOptions.new(write_type: InfluxDB2::WriteType::BATCHING, batch_size: 10, flush_interval: 5_000, max_retries: 3, max_retry_delay: 15_000, exponential_base: 2)
  write_api = client.create_write_api(write_options: write_options)
  write_api.write(data: point)
  rescue InfluxDB2::InfluxError => e
    puts "InfluxDB exception: #{e}"
  end
  sleep 10
end
