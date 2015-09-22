#!/usr/bin/env ruby

require 'rubygems'
require 'mysql2'
require 'optparse'

options = {
  :dbhost => 'localhost',
}

OptionParser.new do |opts|

  opts.banner = "Usage: #{$0} [options]"

  opts.on('-r', '--rstar_dir DIRECTORY', 'R* Directory') do |r|
    options[:rstar_dir] = r
  end

  opts.on('-d', '--dbhost DBHOST', 'MySQL hostname') do |d|
    options[:dbhost] = d
  end

  opts.on('-h', '--help', 'Print help message') do
    puts opts
    exit
  end

end.parse!

ids = []
if ARGV.size > 0
  ids = ARGV
else
  if !options[:rstar_dir]
    abort "You must specify an R* directory."
  elsif !File.directory?(options[:rstar_dir])
    abort "R* directory '#{options[:rstar_dir]}' doesn't exist."
  end
  ids = Dir.glob("#{options[:rstar_dir]}/wip/se/*").map{ |d| File.basename(d) }.sort
end

client = Mysql2::Client.new(
  :host          => options[:dbhost],
  :database      => "task_queue_log",
  :default_file  => "my.cnf")

select_col = client.prepare(
 "SELECT collection_id
  FROM collection
  WHERE provider = ? AND collection = ?")

select_log = client.prepare(
 "SELECT *
  FROM task_queue_log t, collection c
  WHERE t.collection_id = ?
    AND t.wip_id = ?
    AND t.collection_id = c.collection_id")

col_ids = Hash.new

ids.each do |id|
  #p id
  match_data = id.match(/^([a-z_]+)(\d+)$/)
  prov_col_str = match_data[1]
  provider, collection = prov_col_str.split('_')
  wip_id_num = match_data[2]
  #puts provider
  #puts collection
  #puts wip_id_num

  if !col_ids[prov_col_str]
    results = select_col.execute(provider, collection)
    col_ids[prov_col_str] = results.first['collection_id']
  end
  collection_id = col_ids[prov_col_str]
  #puts collection_id
 
  results = select_log.execute(collection_id, wip_id_num)
  if results.count == 0
    puts "#{id}: unknown"
  else
    row = results.first
    puts "#{id}: #{row['state']}"
  end
end

