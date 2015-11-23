#!/usr/bin/env ruby

require 'rubygems'
require 'bunny'
require 'json'
require 'mysql2'
require 'optparse'
require 'yaml'


# Set default options
options = {
  :config  => Dir.pwd + "/config.yml",
  :logfile => Dir.pwd + "/update.log",
}

OptionParser.new do |opts|

  opts.banner = "Usage: #{$0} [options]"

  opts.on('-c', '--config CONFIGFILE', 'Config file (yaml format)') do |c|
    options[:config] = c
  end

  opts.on('-l', '--logfile LOGFILE', 'Log file') do |l|
    options[:logfile] = l
  end

  opts.on('-d', '--daemonize', 'Daemonize process') do
    daemonize = true
  end

  opts.on('-h', '--help', 'Print help message') do
    puts opts
    exit
  end

end.parse!


logger = Logger.new($stderr)

conf_file = options[:config]

if File.exists?(conf_file)
  config = YAML.load_file(conf_file)
else
  abort "Missing config.yaml" 
end

logger.debug "dbhost: #{config["dbhost"]}"

client = Mysql2::Client.new(
  :host     => config["dbhost"],
  :database => config["dbname"],
  :username => config["dbuser"],
  :password => config["dbpass"])

# XXX: create a library for db statemets
insert_col = client.prepare(
 "INSERT INTO collection VALUES (0, ?, ?, ?)")

select_col = client.prepare(
 "SELECT collection_id FROM collection
  WHERE provider = ? AND collection = ?")

insert_log = client.prepare(
 "INSERT INTO task_queue_log VALUES (?, ?, ?, ?)")

update_log = client.prepare(
 "UPDATE task_queue_log SET state = ?, completed = ?
  WHERE collection_id = ? AND wip_id = ?")

select_log = client.prepare(
 "SELECT t.completed FROM task_queue_log t, collection c
  WHERE t.collection_id = c.collection_id
  AND t.collection_id = ? and t.wip_id = ?")

conn = Bunny.new(:host => config['mqhost'])
conn.start

ch = conn.create_channel
x = ch.topic("tq_logging", :auto_delete => true)
q = ch.queue("tq_log_reader", :durable => true)
q.bind(x, :routing_key => "task_queue.*")

q.subscribe(:block => true, :manual_ack => true) do |delivery_info, properties, payload|
  puts "Received #{payload}, message properties are #{properties.inspect}"
  task = JSON.parse(payload)

  # parse rstar_dir to get provider and collection value
  # e.g. /content/prod/rstar/content/nyu/aco/
  # provider = 'nyu', collection = 'aco'
  dirname, collection = File.split(task['rstar_dir'])
  provider = File.basename(dirname)
  logger.debug "provider: #{provider}, collection: #{collection}"

  # split wip_id into prefix and number
  # e.g. nyu_aco000322
  # wip_id_prefix = 'nyu_aco', wip_id_num = '000322'
  logger.debug "wip_id: #{task['identifiers'][0]}"
  match_data = task['identifiers'][0].match(/^(.+?)(\d+)$/)
  logger.debug match_data.inspect
  wip_id_prefix = match_data[1]
  wip_id_num    = match_data[2]
  logger.debug "wip_id_prefix: #{wip_id_prefix}, wip_id_num: #{wip_id_num}"

  results = select_col.execute(provider, collection)
  if results.count == 0
    insert_col.execute(provider, collection, wip_id_prefix)
    collection_id = client.last_id
  else
    collection_id = results.first['collection_id']
  end
  logger.debug "collection_id: #{collection_id}"

  results = select_log.execute(collection_id, wip_id_num)
  if results.count == 0
    logger.debug "Inserting into log for #{wip_id_num}"
    insert_log.execute(collection_id, wip_id_num,
                       task['state'], task['completed'])
  else
    logger.debug "Updating log for #{wip_id_num}"
    update_log.execute(task['state'], task['completed'],
                       collection_id, wip_id_num)
  end

  ch.ack(delivery_info.delivery_tag)
end

conn.close
client.close

# vim: set et:
