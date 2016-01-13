#!/usr/bin/env ruby

require 'rubygems'
require 'logger'
require 'mysql2'
require 'optparse'

options = {
  :my_cnf => "/etc/my-taskqueue.cnf",
}

OptionParser.new do |opts|

  opts.banner = "Usage: #{$0} [options] [wip_ids]... "

  opts.on('-c', '--my-cnf CONFIG FILE', 'MySQL config for taskqueue db') do |c|
    options[:my_cnf] = c
  end

  opts.on('-r', '--rstar-dir DIRECTORY', 'R* directory for collection') do |r|
    options[:rstar_dir] = r
  end

  opts.on('-h', '--help', 'Print help message') do
    puts opts
    exit
  end

end.parse!

logger = Logger.new($stderr)
logger.level = Logger::INFO

if !options[:rstar_dir]
  abort "You must specify an R* directory."
elsif !File.directory?(options[:rstar_dir])
  abort "R* directory '#{options[:rstar_dir]}' doesn't exist."
end

if !File.file?(options[:my_cnf])
  abort "MySQL config file #{options[:my_cnf]} doesn't exist."
end
 
ids = []
if ARGV.size > 0
  ids = ARGV
else
 ids = Dir.glob("#{options[:rstar_dir]}/wip/se/*")
                .map{ |d| File.basename(d) }.sort
end

client = Mysql2::Client.new(
  :default_file  => options[:my_cnf],
)

select_col = client.prepare(
 "SELECT collection_id
  FROM collection
  WHERE provider = ? AND collection = ?")

select_log = client.prepare(
 "SELECT *
  FROM task_queue_log t, collection c
  WHERE t.collection_id = c.collection_id
  AND t.collection_id = ?
  AND t.wip_id = ?")

col_ids = Hash.new

def print_row(id, state, date)
  print id.ljust(20), state.ljust(10), date, "\n"
end

print_row('WIP ID', 'STATUS', 'TIMESTAMP')
puts '-' * 68

ids.each do |id|

  # parse rstar_dir to get provider and collection value
  # e.g. /content/prod/rstar/content/nyu/aco/
  # provider = 'nyu', collection = 'aco'
  dirname, collection = File.split(options[:rstar_dir])
  provider = File.basename(dirname)
  logger.debug "provider: #{provider}, collection: #{collection}"

  prov_col_str = "#{provider}_#{collection}"
  if !col_ids[prov_col_str]
    results = select_col.execute(provider, collection)
    col_ids[prov_col_str] = results.first['collection_id']
  end
  collection_id = col_ids[prov_col_str]
  logger.debug "collection id: #{collection_id}"

  results = select_log.execute(collection_id, id)
  if results.count == 0
    print_row(id, "unknown", "")
  else
    row = results.first
    print_row(id, row['state'], row['completed'])
  end
end

# vim: set et:
