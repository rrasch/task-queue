require 'net/smtp'
require 'yaml'
require 'uri'
require_relative './tqcommon'

class Email

  def initialize(logger)
    @logger = logger
    read_email_addrs
    @smtp_host = TQCommon.get_smtp_host()
    @aliases = TQCommon.get_host_aliases()
  end

  def read_email_addrs
    @logger.debug "entering read_email_addrs()"
    addr_file = "/content/#{TQCommon.get_env()}/rstar/etc/email.yaml"
    @addr = {}
    if File.exist?(addr_file)
      yaml = YAML.load_file(addr_file)
      yaml.each do |id, addr|
        @logger.debug id + ': ' + addr
        if id =~ /^[a-z]+/ && addr =~ URI::MailTo::EMAIL_REGEXP
          @logger.debug "Found valid email #{addr} for #{id}" 
          @addr[id] = addr
        end
      end
    else
      @logger.warn "email map file #{addr_file} doesn't exist"
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
      host = TQCommon.get_hostname(job["worker_host"])
      job["worker_host_alias"] = @aliases.fetch(host, host)
      job.delete('logger')
      out = job.delete('output').to_s.strip
      out = "output:\n#{out}" unless out.empty?
      msg = <<EOM
From: Task Queue <#{mailto}>
To: <#{mailto}>
Subject: #{desc}

#{desc}

#{job.sort.map {|k,v| "#{k}: #{v}"}.join("\n")}

#{out}

EOM
      smtp = Net::SMTP.new(@smtp_host)
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
