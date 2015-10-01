#!/usr/bin/env ruby

require 'rubygems'
require 'bunny'
require 'json'
require 'mysql2'
require 'yaml'

conf_file = "config.yml"

if File.exists?(conf_file)
  # puts "loading #{conf_file}"
  config = YAML.load_file(conf_file)
  # puts config.inspect
else
  abort "Missing config.yaml" 
end

puts config["dbhost"]

client = Mysql2::Client.new(
  :host     => config["dbhost"],
  :database => config["dbname"],
  :username => config["dbuser"],
  :password => config["dbpass"])

select_col = client.prepare(
 "SELECT collection_id FROM collection
  WHERE provider = ? AND collection = ?")

select_log = client.prepare(
 "SELECT * FROM task_queue_log t, collection c
  WHERE t.collection_id = ? AND t.wip_id = ?")

insert_log = client.prepare(
 "INSERT INTO task_queue_log VALUES (?, ?, ?, ?)")

update_log = client.prepare(
 "UPDATE task_queue_log SET state = ?, completed = ?
  WHERE collection_id = ? AND wip_id = ?")

conn = Bunny.new(:host => config['mqhost'])
conn.start

ch = conn.create_channel
x = ch.topic("tq_logging", :auto_delete => true)
q = ch.queue("tq_log_reader", :durable => true)
q.bind(x, :routing_key => "task_queue.*")

q.subscribe(:block => true, :manual_ack => true) do |delivery_info, properties, payload|
  puts "Received #{payload}, message properties are #{properties.inspect}"
  task = JSON.parse(payload)
  puts task['identifiers'][0]
  match_data = task['identifiers'][0].match(/^([a-z_]+)(\d+)$/)
  provider, collection = match_data[1].split('_')
  wip_id_num = match_data[2]
  puts provider
  puts collection
  puts wip_id_num
  results = select_col.execute(provider, collection)
  collection_id = results.first['collection_id']

  results = select_log.execute(1, wip_id_num)
  if results.count == 0
    insert_log.execute(collection_id, wip_id_num,
      task['state'], task['completed'])
  else
    update_log.execute(task['state'], task['completed'],
      collection_id, wip_id_num)
  end
end

