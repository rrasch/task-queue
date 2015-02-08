#!/usr/bin/env ruby
#
# Preforking RabbitMQ job runner using Servolux.
#
# In this example, we prefork 7 processes each of which connect to our
# RabbitMQ queue and then wait for jobs to process. We are using a module so
# that we can connect to the RabbitMQ queue before executing and then
# disconnect from the RabbitMQ queue after exiting. These methods are called
# exactly once per child process.
#
# A variation on this is to load source code in the before_executing method
# and initialize an object that will process jobs. This is advantageous because
# now you can send SIGHUP to a child process and it will restart, loading your
# Ruby libraries before executing. Now you can do a rolling deploy of new
# code.
#
#   def before_executing
#     Kernel.load '/your/source/code.rb'
#     @job_runner = Your::Source::Code::JobRunner.new
#   end
# --------

require 'rubygems'
require 'bunny'
require 'json'
require 'logger'
require 'servolux'
require_relative './lib/bagit'
require_relative './lib/book_publisher'

module JobProcessor
  # Open a connection to our RabbitMQ queue. This method is called once just
  # before entering the child run loop.
  def before_executing
    puts "before_executing"
    mqhost = 'localhost'
    foo = fuck
    begin
      puts "Connecting to #{mqhost}"
      @conn = Bunny.new(:host => mqhost, :automatically_recover => true)
      @conn.start
      @ch = @conn.create_channel
      @q = @ch.queue("task_queue", :durable => true)
      @ch.prefetch(1)
    rescue Bunny::TCPConnectionFailed => e
      puts "Connection to #{mqhost} failed #{e}"
    rescue Exception => e
      puts e
    end
  end

  # Close the connection to our RabbitMQ queue. This method is called once
  # just after the child run loop stops and just before the child exits.
  def after_executing
    puts $?
    puts "after_executing"
    @conn.close
  end

  # Close the RabbitMQ socket when we receive SIGHUP. This allows the execute
  # thread to return processing back to the child run loop; the child run loop
  # will gracefully shutdown the process.
  def hup
    @conn.close
    @thread.wakeup
  end

  # We want to do the same thing when we receive SIGTERM.
  alias :term :hup

  # Reserve a job from the RabbitMQ queue, and processes jobs as we receive
  # them. We have a timeout set for 2 minutes so that we can send a heartbeat
  # back to the parent process even if the RabbitMQ queue is empty.
  #
  # This method is called repeatedly by the child run loop until the child is
  # killed via SIGHUP or SIGTERM or halted by the parent.
  def execute
    puts "execute"
    @q.subscribe(:manual_ack => true, :block => true) do |delivery_info, properties, body|
      puts " [x] Received '#{body}'"
      task = JSON.parse(body)
      p task
      #class_name = classify(task['class'])
      class_name = task['class']
      obj = Object::const_get(class_name).new
      obj.rstar_dir = task['rstar_dir']
      obj.ids = task['identifiers']
      method_name = task['operation'].tr('-', '_')
      obj.send(method_name)
      puts " [x] Done"
      @ch.ack(delivery_info.delivery_tag)
    end
  rescue Interrupt => _
    @ch.close
    @conn.close
  ensure
  end
end

def classify(str)
  str.split(/[_-]/).collect(&:capitalize).join
end

# Create our preforking worker pool. Each worker will run the code found in
# the JobProcessor module. We set a timeout of 10 minutes. The child process
# must send a "heartbeat" message to the parent within this timeout period;
# otherwise, the parent will halt the child process.
#
# Our execute code in the JobProcessor takes this into account. It will wakeup
# every 2 minutes, if no jobs are reserved from the RabbitMQ queue, and send
# the heartbeat message.
#
# This also means that if any job processed by a worker takes longer than 10
# minutes to run, that child worker will be killed.
pool = Servolux::Prefork.new(:timeout => 600, :module => JobProcessor)

# Start up 7 child processes to handle jobs
pool.start 1
puts "Waiting"

# When SIGINT is received, kill all child process and then reap the child PIDs
# from the proc table.
trap('INT') {
  pool.signal 'KILL'
  pool.reap
}
Process.waitall

# vim: et:
