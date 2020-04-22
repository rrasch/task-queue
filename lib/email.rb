require 'net/smtp'
require 'yaml'
require 'uri'

class Email

  ADDR_FILE = "/content/prod/rstar/etc/email.yaml"

  def initialize(logger)
    @logger = logger
    read_email_addrs
  end

  def read_email_addrs
    @logger.debug "entering read_email_addrs()"
    @addr = {}
    if ADDR_FILE && File.exist?(ADDR_FILE)
      yaml = YAML.load_file(ADDR_FILE)
      yaml.each do |id, addr|
        @logger.debug id + ': ' + addr
        if id =~ /^[a-z]+/ && addr =~ URI::MailTo::EMAIL_REGEXP
          @logger.debug "Found valid email #{addr} for #{id}" 
          @addr[id] = addr
        end
      end
    else
      @logger.debug "email map file #{ADDR_FILE} doesn't exist"
    end
    @logger.debug "email map: #{@addr}"
  end

  def send(task)
    @logger.debug "entering send()"
    mailto = @addr[task['user_id']]
    @logger.debug "user_id: #{task['user_id']}, mailto: #{mailto}"

    if mailto
      desc  = "Job #{task['job_id']} completed "
      desc += "un" if task['state'] == 'error'
      desc += "successfully at #{task['completed']}"
      job = task.clone
      job.delete('output')
      msg = <<EOM
From: Task Queue <#{mailto}>
To: <#{mailto}>
Subject: #{desc}

#{desc}

#{job.sort.map {|k,v| "#{k}:#{v}"}.join("\n")}
output:
#{task['output'].to_s}

EOM
      smtp = Net::SMTP.new('localhost')
      smtp.open_timeout = 5
      smtp.read_timeout = 5
      smtp.start do |smtp|
        res = smtp.send_message msg, mailto, mailto
        @logger.debug "response: #{res.string}" if res
      end
    else
      @logger.debug "Can't find email address for #{task['user_id']}"
    end
  rescue Exception => ex
    @logger.error %Q[#{ex.class} #{ex.message}\n#{ex.backtrace.join("\n")}]
  end

end

