require 'json'
require 'net/http'
require 'csv'

#FINGERPRINTS = [
#/доступ\s+к\s+[а-яa-z\/:\.э\s"'«»]+\s+ограничен/i,
#/Ресурс\s+заблокирован/i, 
#/доступ\s+[а-яa-z\/:\.э\s"'«»]*\s*запрещен/i, 
#/доступ\s+[а-яa-z\/:\.э\s"'«»]*\s*заблокирован/i, 
#/страница\s+[а-яa-z\/:\.э\s"'«»]*\s*заблокирована/i, 
#/ссылка\s+[а-яa-z\/:\.э\s"'«»]*\s*заблокирована/i, 
#/сайт\s+[а-яa-z\/:\.э\s"'«»]*\s*заблокирован/i]


FINGERPRINTS = [
/доступ\s+к\s+[а-яa-z\/:\.іїє\s"'«»]+\s+обмежен/i,
/Ресурс\s+заблоков/i, 
/доступ\s+[а-яa-z\/:\.іїє\s"'«»]*\s*заборонен/i, 
/доступ\s+[а-яa-z\/:\.іїє\s"'«»]*\s*заблокован/i, 
/сторінка\s+[а-яa-z\/:\.іїє\s"'«»]*\s*заблокована/i, 
/посилання\s+[а-яa-z\/:\.іїє\s"'«»]*\s*заблокирован/i, 
/сайт\s+[а-яa-z\/:\.іїє\s"'«»]*\s*заблокован/i]

city = ARGV[0]
month = ARGV[1]
islocal = ARGV[2] ? "_local" : ""

reports = CSV.read("#{city}_ids_#{month}#{islocal}_uniq.csv")
count = reports.count

CSV.open("#{city}_measurements_#{month}#{islocal}.csv", "ab") do |data|
   data << %w(measurement_id week website asn provider status blocking_reason failure code date dns_query dns_control text what recheck)
end

def get_measurements(url)
  uri = URI.parse(URI.escape(url))
  res = Net::HTTP.get_response(uri)
  results = JSON.parse(res.body)
  {m: results['results'], n: results['metadata']['next_url']}
end

reports.each do |report|

  puts report[0]

  measurements = []
  week = report[1]
  provider = report[2]
  url = "https://api.ooni.io/api/v1/measurements?report_id="+report[0].strip
  while url
    measurements = measurements + get_measurements(url)[:m] 
    url = get_measurements(url)[:n]
  end

  measurements.each do |m|
  
    arr = []
    uri = URI.parse(URI.escape(m['measurement_url']))
    res = Net::HTTP.get_response(uri)
    mment = JSON.parse(res.body)
    measurement_id = m['measurement_id']
    website = m['input']
    asn = m['probe_asn'] 
    begin
      if mment['test_keys']['control_failure']
        status = 'control_failure' 
      else
        status = mment['test_keys']['accessible']
      end

      if status == false
        blocking_reason = mment['test_keys']['blocking'] 

        request = mment['test_keys']['requests'][0]
        response = mment['test_keys']['requests'][0]['response']

        failure = request['failure']

        if response
          code = response['code'] 
          date = response['headers']['Date'] 
          body = response['body']
        end

        if mment['test_keys']['blocking'] == 'dns'
          begin
            if mment['test_keys']['queries'][0]['answers'].empty?
              dns_query = mment['test_keys']['queries'][0]['failure'] 
            else       
              dns_query = mment['test_keys']['queries'][0]['answers'][1]['ipv4'] 
              dns_control = mment['test_keys']['control']['dns']['addrs'] 
            end
            if mment['test_keys']['queries'].count > 1
              puts "recheck dns queries "+mment['measurement_url']+" ("+website+")"
            end
          rescue
            puts mment['measurement_url']+ " dns check fail"
            next
          end
        end
        if body
          match = 0
          if body['format'] && body['format']=='base64'
            if body['data'].match(/PGh0bWw\+DQo8aGVhZD4NCjx0aXRsZT7E7vHy8/)
              match = 1    
              text = 'base64 fingerprint' 
            else
              text = 'base64, recheck' 
            end
          else 
            stripped = strip_tags(body)
            clean = stripped.gsub("\t"," ").gsub("\r"," ").gsub("\n"," ")
            FINGERPRINTS.each do |fp|
              if clean.match(fp)
                match = 1
                text = clean 
              end
            end
            if clean.match(/403 Forbidden/i)
              match = 2
            elsif clean.match(/451 Unavailable for Legal Reasons/i)
              match = 3
            elsif clean.match(/CAPTCHA/i)
              match = 4
            end
            if match == 1
              what = 'blocking page'
            elsif match == 2 
              what = '403 forbidden'   
            elsif match == 3  
              what = 'blocking page(451)'     
            elsif match == 4 
              what = 'captcha'     
            else   
              what = ''                  
              recheck = 'recheck'  
            end
          end
        end
      end
    rescue
      puts mment['measurement_url'].to_s+" ("+website+") failed"
      next
    end
    arr = [measurement_id, week, website, asn, provider, status, blocking_reason, failure, code, date, dns_query, dns_control, text, what, recheck]
    
    CSV.open("#{city}_measurements_#{month}#{islocal}.csv", "ab") do |data|
      data << arr
    end

  end
end

