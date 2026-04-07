#!/usr/bin/env ruby

require 'rubygems'
require 'logger'
require 'optparse'
require 'socket'
require_relative './lib/joblog'

Signal.trap('SIGPIPE', 'SYSTEM_DEFAULT')

def print_batch_report(counts, start_id, end_id)
  states = %w[success processing error pending]

  total = counts.values.sum

  separator = '-' * 27

  puts separator
  puts " Batch #{start_id} #{end_id} Status Report"
  puts separator

  st_col_width = 10
  states.each do |state|
    puts "#{state.rjust(st_col_width)}  :  #{counts[state]}"
  end

  puts separator
  puts 'total'.rjust(st_col_width) + "  :  #{total}"
end

def parse_opts
  options = {}

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] START_ID [END_ID]"

    opts.on('-v', '--verbose', 'Enable debugging messages') do
      options[:verbose] = true
    end

    opts.on('-h', '--help', 'Print help message') do
      puts opts
      exit
    end
  end

  parser.parse!

  begin
    case ARGV.length
    when 1
      start_id = end_id = Integer(ARGV[0])
    when 2
      start_id = Integer(ARGV[0])
      end_id   = Integer(ARGV[1])
      abort 'Error: START_ID must be <= END_ID' if start_id > end_id
    else
      abort parser.to_s
    end
  rescue ArgumentError
    abort 'Error: START_ID and END_ID must be integers'
  end

  options[:batch_id] = [start_id, end_id]

  options
end

def main
  env = /^d/ =~ Socket.gethostname ? 'dev' : 'prod'
  my_cnf = "/content/#{env}/rstar/etc/my-taskqueue.cnf"

  options = parse_opts
  logger = Logger.new($stderr)
  logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO

  counts = Hash.new(0)
  joblog = JobLog.new(my_cnf, logger)

  joblog.state_counts(options).each do |row|
    counts[row['state']] = row['count']
  end

  print_batch_report(counts, *options[:batch_id])
end

if __FILE__ == $PROGRAM_NAME
  main
end
