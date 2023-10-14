#!/usr/bin/env ruby

require 'rubygems'
require 'chronic'
require 'io/console'
require 'json'
require 'logger'
require 'optparse'
require 'pp'
require 'resolv'
require 'socket'
require 'yaml'
require_relative './lib/joblog'


def get_host_aliases(alias_file)
  aliases = {}
  if File.exist?(alias_file)
    aliases = YAML.load_file(alias_file)["aliases"]
    aliases = aliases.map { |name, nick| [name[/^[^.]+/], nick] }.to_h
  end
  return aliases
end

def fmt_date(date)
  date.nil? || date.is_a?(String) ? date : date.strftime('%D %T')
end

def sql_date(human_date)
  Chronic.parse(human_date).strftime('%Y-%m-%d %H:%M:%S')
end

def duration(start_date, end_date)
  return "" if start_date.nil? || end_date.nil?
  secs = (end_date - start_date).to_i
  min, secs = secs.divmod(60)
  hours, min = min.divmod(60)
  days, hours = hours.divmod(24)
  tm = []
  tm << "#{days}d"  if days.nonzero?
  tm << "#{hours}h" if hours.nonzero?
  tm << "#{min}m"   if min.nonzero?
  tm << "#{secs}s"  if secs.nonzero? || tm.empty?
  tm.join(", ")
end

def fmt(val, length=20, left_justify=true)
  val = val || ""
  if left_justify
    val.ljust(length)
  else
    val.rjust(length)
  end
end

def print_row(batch_id, id, state, host, started,
              completed, duration, objid, op, user_id)
  if /\A(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\Z/ =~ host
    begin
      host = Resolv.getname(host)[/^[^.]+/].downcase
    rescue Resolv::ResolvError => e
      # Do nothing
    end
  end
  host = $host_aliases.fetch(host, host)
  print fmt(batch_id.to_s, 8, false) if $is_large_win
  print fmt(id.to_s, 8, false), fmt('', 2), fmt(state, 11), fmt(host, 16),
        fmt(fmt_date(started), 20), fmt(fmt_date(completed), 20)
  if $is_large_win
    print fmt(duration, 16)
    print fmt(objid, 30)
    print fmt(op, 20)
    print fmt(user_id, 12)
  end
  print "\n"
end


env = /^d/ =~ Socket.gethostname ? "dev" : "prod"

etcdir = "/content/#{env}/rstar/etc"

alias_file = "#{etcdir}/host_aliases.yaml"

options = {
  :my_cnf => "#{etcdir}/my-taskqueue.cnf",
  :limit => "100",
# :from => '3 days ago',
# :to => 'now',
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

  opts.on('-o', '--output', 'Print output for jobs') do
    options[:output] = true
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

win_rows, win_cols = IO.console.winsize
$is_large_win = win_cols > 120

$host_aliases = get_host_aliases(alias_file)

options[:from] = sql_date(options[:from]) if options.key?(:from)
options[:to] = sql_date(options[:to]) if options.key?(:to)

if options.key?(:from) && options.key?(:to) &&
    options[:from] >= options[:to]
  puts "Make sure start date '#{options[:from]}' occurs before "\
       "end date '#{options[:to]}'."
  exit 1
end

joblog = JobLog.new(options[:my_cnf], logger)

sep = '-' * win_cols

if !options[:batch_id].nil?
  batch = joblog.select_batch(options[:batch_id])
  if !batch.nil?
    puts "\nBATCH ##{options[:batch_id]}"
    puts sep
    batch.each do |key, value|
      puts key + ': ' + value.to_s
    end
    puts sep
    puts
  end
end

puts sep
print_row(
  'BATCH ID',
  'JOB ID',
  'STATUS',
  'HOST',
  'STARTED',
  'COMPLETED',
  'DURATION',
  'ID',
  'SERVICE',
  'USER ID'
)
puts sep

joblog.select_job(options).each do |row|
  req = JSON.parse(row['request'])
  ids = req['identifiers']
  input = req['input_path']

  if ids
    id = ids[0]
  elsif input
    id = File.basename(input, ".*")
    id = id.gsub(/(_\d{6})?_[dm]$/, '')
  else
    id = "N/A"
  end

  print_row(
    row['batch_id'],
    row['job_id'],
    row['state'],
    row['worker_host'],
    row['started'],
    row['completed'],
    duration(row['started'], row['completed']),
    id,
    req['operation'],
    row['user_id'],
  )
  if options[:output]
    if row['output']
      puts sep
      puts row['output']
    end
    puts sep
  end
end

# vim: set et:
