require 'json'
require 'net/http'
require 'csv'

#initial data collection
#requires an input file with columns: report_id, week number, provider

IDS_FILE = ARGV[0]
OUT_FILE = ARGV[1]


rows = CSV.read(IDS_FILE)

def get_measurements(url)
  uri = URI.parse(URI.escape(url))
  res = Net::HTTP.get_response(uri)
  results = JSON.parse(res.body)
  {m: results['results'], n: results['metadata']['next_url']}
end

rows.each do |row|

  measurements = []
  week = row[1]
  provider = row[2]
  url = "https://api.ooni.io/api/v1/measurements?report_id="+row[0]
  while url
    puts url
    measurements = measurements + get_measurements(url)[:m]
    puts measurements.count
    url = get_measurements(url)[:n]
  end
  puts "m total "+measurements.count.to_s
  measurements.each do |r|
    arr = []
    input = r['input']
    asn = r['probe_asn']
    uri = URI.parse(URI.escape(r['measurement_url']))
    res = Net::HTTP.get_response(uri)
    mment = JSON.parse(res.body)
    arr[0] = r['measurement_id']
    arr[1] = r['report_id']
    arr[2] = r['input']
    begin
      arr[3] = mment['test_keys']['accessible']
      arr[4] = mment['test_keys']['blocking']
      arr[5] = mment['test_keys']['control_failure']
      arr[6] = asn
      arr[7] = provider
      arr[8] = week
    rescue
      puts r['measurement_url'].to_s+" failed"
      next
    end
    CSV.open(OUT_FILE, "ab") do |data|
      data << arr
    end

  end
  sleep 1
end

