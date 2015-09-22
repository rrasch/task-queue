#!/usr/bin/env ruby

require 'rubygems'
require 'bunny'
require 'json'
require 'mysql2'

client = Mysql2::Client.new(
  :host     => "localhost",
  :username => "tquser",
  :password => "mypasswd",
  :database => "task_queue_log")

select_col = client.prepare("SELECT collection_id FROM collection WHERE provider = ? AND collection = ?")

select_log = client.prepare("SELECT * from task_queue_log t, collection c WHERE t.collection_id = ? AND t.wip_id = ?")
insert_log = client.prepare("INSERT INTO task_queue_log VALUES (?, ?, ?, ?)")
update_log = client.prepare("UPDATE task_queue_log SET state = ?, completed = ? WHERE collection_id = ? AND wip_id = ?")

conn = Bunny.new
conn.start

ch = conn.create_channel
x = ch.topic("tq_logging", :auto_delete => true)
q = ch.queue("tq_log_reader", :durable => true)
q.bind(x, :routing_key => "task_queue.*")

q.subscribe(:block => true, :ack => false) do |delivery_info, properties, payload|
  puts "Received #{payload}, message properties are #{properties.inspect}"
  task = JSON.parse(payload)
  p task['identifiers'][0]
  match_data = task['identifiers'][0].match(/^([a-z_]+)(\d+)$/)
  provider, collection = match_data[1].split('_')
  wip_id_num = match_data[2]
  p provider
  p collection
  p wip_id_num
  results = select_col.execute(provider, collection)
  collection_id = results.first['collection_id']

  results = select_log.execute(1, wip_id_num)
  if results.count == 0
    insert_log.execute(collection_id, wip_id_num, task['state'], task['completed'])
  else
    update_log.execute(task['state'], task['completed'], collection_id, wip_id_num)
  end
end

