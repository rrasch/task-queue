#!/usr/bin/env ruby
# encoding: utf-8

require "bunny"

conn = Bunny.new(:automatically_recover => false)
conn.start

ch = conn.create_channel
q = ch.queue("task_queue", :durable => true)

ch.default_exchange.publish("/home/rasan", :routing_key => q.name)
puts " [x] Sent 'Hello World!'"

conn.close

