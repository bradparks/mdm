# encoding: UTF-8
#$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)

require 'rubygems'
require 'bundler'
require 'logger'
require 'yaml'
require 'ruby-debug'
Bundler.require

MDM_DIR = File.dirname(__FILE__)

APNS.host = 'gateway.push.apple.com'
APNS.pem = "#{File.join(MDM_DIR, 'certs', 'apns-push.pem')}"

ApplePush.host = 'gateway.push.apple.com'
ApplePush.port = 2195

class MDMServer < Sinatra::Base

=begin
  configure :development do
    LOGGER = Logger.new("#{File.dirname(__FILE__)}/log/development.log")
    LOGGER.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime("%Y%M%D %h:%m:%s")}:#{progname}:#{severity}: #{msg}\n"
    end
    enable :logging, :dump_errors
    set :raise_errors, true
  end

  error do
    e = request.env['sinatra.error']
    puts "-"*40
    puts "#{Time.now.strftime("%Y%M%D %h:%m:%s")}\n"
    puts e.to_s
    puts e.backtrace.join("\n")
    puts "-"*40
    "Application Error!"
  end

  helpers do
    def logger
      LOGGER
    end
  end
=end

  def req_plist(request)
    plist = nil
    begin
      body = request.body.read
      puts body 
      plist = Plist.parse_xml(body)
    rescue => e
    end

    return plist
  end

  #$ curl -kD - -X PUT https://localhost:8443/mdm_checkin
  put '/mdm_checkin' do
    #begin
      plist = req_plist(request)
      puts "No MessageType, WTF?" unless plist.keys.include?("MessageType")
      puts "No UDID, WTF?" unless plist.keys.include?("UDID")
      dev_file = "#{File.join(MDM_DIR, "devices", plist['UDID'])}.device"

      case plist['MessageType']
      when 'Authenticate'
        return {}.to_plist
      when 'TokenUpdate'
        dev_info = {}
        %w(PushMagic Token UnlockToken).each { |pk|
          if plist.keys.include?(pk)
            if plist[pk].class == String
              dev_info[pk] = plist[pk]
            elsif plist[pk].class == StringIO
              dev_info[pk] = Base64.encode64(plist[pk].read)
            end
          end
        }
        open(dev_file, 'wb+') { |df| df << dev_info.to_yaml }
        return {}.to_plist
      end
  #  rescue => e
  #    puts "checkin error: #{e}"
  #  end
    {}.to_plist
  end

  put '/mdm_server' do
    #begin
      plist = req_plist(request)
      dev_file = "#{File.join(MDM_DIR, "devices", plist['UDID'])}.device"

      case plist['Status']
      when 'Idle'
        dev_avail_cap = {
          'Command' => {'RequestType' => 'DeviceInformation', 
                        'Queries' => ["AvailableDeviceCapacity"]}, 
          'CommandUUID' => UUID.generate
        }.to_plist

        puts dev_avail_cap
        return dev_avail_cap
      else
        # XXX log response
        puts plist
      end

    #rescue => e
    #end
    {}.to_plist
  end

  get '/push' do
    results = []
    Dir["#{MDM_DIR}/devices/*.device"].each { |dfn|
      begin
        puts "[d] opening #{dfn}"
        dev_info = YAML.load_file(dfn)
        #puts "[d] token: #{dev_info['Token']}"
        #puts "[d] pushmagic: #{dev_info['PushMagic']}"
        #puts "[d] packaged token: #{}"
        #nm = APNS::Notification.new(dev_info['Token'],
        #                            :other => {:mdm=> dev_info['PushMagic']})
        #puts "[d] #{nm.packaged_notification}"
        #res = APNS.send_notifications([nm])
        pem = "#{File.join(MDM_DIR, 'certs', 'apns-push.pem')}"
        tok = dev_info['Token']
        pm = dev_info['PushMagic']

        ApplePush.send_notification(pem, tok, :other => { :mdm => pm })
        results << File.basename(dfn)
      rescue => e
        puts "[x] error: #{e}"
      end
    }
    "[*] sent notifications to #{results.length} devices (#{results.join(', ')})"
  end

  get '/ca' do
    if File.exist?("#{MDM_DIR}/certs/ca.crt")
      headers \
        "Content-Type"   => 'application/octet-stream;charset=utf-8',
        "Content-Disposition" => 'attachment;filename="ca.crt"'
      return open("#{MDM_DIR}/certs/ca.crt", "rb").read()
    else
      return "no ca certificate available"
    end
  end
end
