#!/usr/bin/env ruby

require 'rubygems'
require 'chronic'
require 'logger'
require 'optparse'
require 'resolv'
require './lib/joblog'

options = {
  :my_cnf => "/content/prod/rstar/etc/my-taskqueue.cnf",
  :limit => 100,
  :from => '3 days ago',
  :to => 'now',
}

OptionParser.new do |opts|

  opts.banner = "Usage: #{$0} [options]"

  opts.on('-c', '--my-cnf CONFIG_FILE', 'MySQL config for taskqueue db') do |c|
    options[:my_cnf] = c
  end

  opts.on('-b', '--batch-id NUMBER', 'Query jobs from batch id') do |b|
    options[:batch_id] = b
  end

  opts.on('-f', '--from DATETIME', 'Query jobs from date') do |f|
    options[:from] = f
  end

  opts.on('-t', '--to DATETIME', 'Query jobs to date') do |t|
    options[:to] = t
  end

  opts.on('-l', '--limit LIMIT', 'Limit results to this number') do |l|
    options[:limit] = l
  end

  opts.on('-v', '--verbose', 'Enable debugging messages') do
    options[:verbose] = true
  end

  opts.on('-h', '--help', 'Print help message') do
    puts opts
    exit
  end

end.parse!

logger = Logger.new($stderr)
logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO

if !File.file?(options[:my_cnf])
  abort "MySQL config file #{options[:my_cnf]} doesn't exist."
end
 
def fmt_date(date)
  date.nil? || date.is_a?(String) ? date : date.strftime('%D %T')
end

def sql_date(human_date)
  Chronic.parse(human_date).strftime('%Y-%m-%d %H:%M:%S')
end

def fmt(val, length=20, left_justify=true)
  val = val || ""
  if left_justify
    val.ljust(length)
  else
    val.rjust(length)
  end
end

def print_row(id, state, host, started, completed)
  if /\A(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\Z/ =~ host
    begin
      host = Resolv.getname(host)[/^[^.]+/].downcase
    rescue Resolv::ResolvError => e
      # Do nothing
    end
  end
  print fmt(id.to_s, 8, false), fmt('', 2), fmt(state, 11), fmt(host, 16),
        fmt(fmt_date(started), 20), fmt_date(completed), "\n"
end

options[:from] = sql_date(options[:from]) if options.key?(:from)
options[:to] = sql_date(options[:to]) if options.key?(:to)

puts
print_row('JOB ID', 'STATUS', 'HOST', 'STARTED', 'COMPLETED')
puts '-' * 80

JobLog.new(options[:my_cnf], logger).select_job(options).each do |row|
  print_row(
    row['job_id'],
    row['state'],
    row['worker_host'],
    row['started'],
    row['completed']
  )
end

# vim: set et:
