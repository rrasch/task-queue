#!/usr/bin/env ruby

require 'rubygems'
require 'chronic'
require 'csv'
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
    print fmt(objid[0, 39], 40)
    print fmt(op, 20)
    print fmt(user_id, 12)
  end
  print "\n"
end

Signal.trap("SIGPIPE", "SYSTEM_DEFAULT")

env = /^d/ =~ Socket.gethostname ? "dev" : "prod"

etcdir = "/content/#{env}/rstar/etc"

alias_file = "#{etcdir}/host-aliases.yaml"

options = {
  :my_cnf => "#{etcdir}/my-taskqueue.cnf",
}

DEFAULT_LIMIT = 100


ID_RANGE = Object.new

OptionParser.accept(ID_RANGE) do |s|
  case s
  when /\A\d+\z/
    s.to_i

  when /\A\d+[-:]\d+\z/
    start_id, end_id = s.split(/[-:]/).map(&:to_i)

    if start_id > end_id
      raise OptionParser::InvalidArgument, 'start > end in range'
    end

    [start_id, end_id]

  else
    raise OptionParser::InvalidArgument,
          'must be a number or range (e.g. 100 or 100-105 or 100:105)'
  end
end


OptionParser.new do |opts|

  opts.banner = "Usage: #{$0} [options]"

  opts.on('-c', '--my-cnf CONFIG_FILE', 'MySQL config for taskqueue db') do |c|
    options[:my_cnf] = c
  end

  opts.on('-b', '--batch-id ID', ID_RANGE,
          'Query jobs with batch id (e.g. 123, 100-105, 200:210)') do |b|
    options[:batch_id] = b
  end

  opts.on('-f', '--from DATETIME', 'Query jobs from date') do |f|
    options[:from] = f
  end

  opts.on('-t', '--to DATETIME', 'Query jobs to date') do |t|
    options[:to] = t
  end

  opts.on('-l', '--limit LIMIT', Integer, 'Limit results to this number') do |l|
    options[:limit] = l
  end

  opts.on("--csv [FILE]", "Write output to CSV (default: jobs.csv)") do |file|
    options[:csv] = file || "jobs.csv"
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

unless options[:limit] || options[:batch_id]
  options[:limit] = DEFAULT_LIMIT
end

logger = Logger.new($stderr)
logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO

if !File.file?(options[:my_cnf])
  abort "MySQL config file #{options[:my_cnf]} doesn't exist."
end

win_rows, win_cols = IO.console&.winsize || [24, 80]
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

if options[:csv]
  result = joblog.select_job(options)
  headers = %w[
    job_id batch_id state user_id worker_host submitted started completed
  ]
  CSV.open(options[:csv], "w", write_headers: true, headers: headers) do |csv|
    result.each do |row|
      csv << headers.map { |h| row[h] }
    end
  end
  puts "CSV written to #{options[:csv]}"
  exit
end

sep = '-' * win_cols

if !options[:batch_id].nil?
  joblog.select_batch(options[:batch_id]).each do |batch|
    puts "BATCH ##{batch['batch_id']}"
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
    if id =~ /^(aux|data)$/
      id = File.basename(File.dirname(input), ".*")
    end
    id = id.gsub(/_[dm]$/, '')
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
