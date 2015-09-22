#!/usr/bin/env ruby

require 'rubygems'
require 'bunny'
require 'json'
require 'mysql2'

client = Mysql2::Client.new(
  :host     => "localhost",
  :username => "tquser",
  :password => "mypasswd",
  :database => "task_queue")

select = client.prepare("SELECT * from task_queue t, collection c WHERE t.collection_id = ? AND t.wip_id = ?")
insert = client.prepare("INSERT INTO task_queue VALUES (?, ?, ?)")
update = client.prepare("UPDATE SET task_queue VALUES (?, ?, ?) WHERE WHERE collection_id = ? AND wip_id = ?")

conn = Bunny.new
conn.start

ch = conn.create_channel
q = ch.queue("task_queue.complete")

q.subscribe(:block => true, :ack => false) do |delivery_info, properties, payload|
  puts "Received #{payload}, message properties are #{properties.inspect}"
  task = JSON.parse(payload)
  p task['identifiers'][0]
  wip_id_num = task['identifiers'][0].tr('A-Za-z_', '')
  p wip_id_num
  results = select.execute(1, wip_id_num)
  if results.count == 0
    insert.execute(1, wip_id_num, task['completed'])
  else
    update.execute(1, wip_id_num, task['completed'])
  end
end



