# frozen_string_literal: true

require 'net/smtp'
require 'yaml'
require 'uri'
require_relative './tqcommon'

# Sends email notifications for job status.
class Email
  def initialize(logger)
    @logger = logger
    read_email_addrs
    @smtp_host = TQCommon.smtp_host
    @aliases = TQCommon.host_aliases
  end

  def build_addr_map(addr_file)
    addr_map = {}
    yaml = YAML.load_file(addr_file)
    yaml.each do |id, addr|
      @logger.debug "#{id}: #{addr}"
      if id =~ /^[a-z]+/ && addr =~ URI::MailTo::EMAIL_REGEXP
        @logger.debug "Found valid email #{addr} for #{id}"
        addr_map[id] = addr
      end
    end
    addr_map
  end

  def read_email_addrs
    @logger.debug 'entering read_email_addrs()'
    addr_file = "/content/#{TQCommon.env}/rstar/etc/email.yaml"
    @addr = {}
    if File.exist?(addr_file)
      @addr = build_addr_map(addr_file)
    else
      @logger.warn "email map file #{addr_file} doesn't exist"
    end
    @logger.debug "email map: #{@addr}"
  end

  def build_desc(task)
    desc  = "Job #{task['job_id']} completed "
    desc += 'un' if task['state'] == 'error'
    desc += "successfully at #{task['completed']}"
    desc
  end

  def display_values(task)
    desc = build_desc(task)
    job = task.clone
    host = TQCommon.hostname(job['worker_host'])
    job['worker_host_alias'] = @aliases.fetch(host, host)
    job.delete('logger')
    output = job.delete('output').to_s.strip
    output = "output:\n#{output}" unless output.empty?
    [job, desc, output]
  end

  def format_email(mailto, desc, job, output)
    <<~EMAIL
      From: Task Queue <#{mailto}>
      To: <#{mailto}>
      Subject: #{desc}

      #{desc}

      #{job.sort.map { |k, v| "#{k}: #{v}" }.join("\n")}

      #{output}

    EMAIL
  end

  def deliver_email(mailto, msg)
    smtp = Net::SMTP.new(@smtp_host)
    smtp.open_timeout = 5
    smtp.read_timeout = 5
    smtp.start do |conn|
      res = conn.send_message msg, mailto, mailto
      @logger.debug "response: #{res.string}" if res
    end
  rescue StandardError => e
    @logger.error %(#{e.class} #{e.message}\n#{e.backtrace.join("\n")})
  end

  def send(task)
    @logger.debug 'entering send()'
    mailto = @addr[task['user_id']]
    @logger.debug "user_id: #{task['user_id']}, mailto: #{mailto}"
    unless mailto
      @logger.debug "Can't find email address for #{task['user_id']}"
      return
    end
    job, desc, output = display_values(task)
    msg = format_email(mailto, desc, job, output)
    deliver_email(mailto, msg)
  end
end
