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
require './lib/bagit'
require './lib/book_publisher'

module Logging
  # This is the magical bit that gets mixed into your classes
  def logger
    Logging.logger
  end

  # Global, memoized, lazy initialized instance of a logger
  def self.logger
    @logger ||= ::Logger.new( $stderr )
  end
end

module JobProcessor

  include Logging

  # Open a connection to our RabbitMQ queue. This method is called once just
  # before entering the child run loop.
  def before_executing
    logger.debug "JobProcessor logger id: #{logger.__id__}"
    logger.debug "before_executing"
    begin
      logger.debug "Connecting to #{$mqhost}"
      @conn = Bunny.new(:host => $mqhost, :automatically_recover => true)
      @conn.start
      @ch = @conn.create_channel
      @q = @ch.queue("task_queue", :durable => true)
      @ch.prefetch(1)
    rescue Bunny::TCPConnectionFailed => e
      logger.fatal "Connection to #{$mqhost} failed #{e}"
      exit 1
    rescue Exception => e
      logger.fatal e
      exit 1
    end
  end

  # Close the connection to our RabbitMQ queue. This method is called once
  # just after the child run loop stops and just before the child exits.
  def after_executing
    puts $?
    logger.debug "after_executing"
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
    logger.debug "execute"
    @q.subscribe(:manual_ack => true, :block => true) do |delivery_info, properties, body|
      puts " [x] Received '#{body}'"
      task = JSON.parse(body)
      p task
      class_name = classify(task['class'])
      #class_name = task['class']
      obj = Object::const_get(class_name).new
      obj.rstar_dir = task['rstar_dir']
      obj.ids = task['identifiers']
      obj.logger = logger
      method_name = task['operation'].tr('-', '_')
      obj.send(method_name)
      puts " [x] Done"
      @ch.ack(delivery_info.delivery_tag)
    end
  rescue Interrupt => _
    @ch.close
    @conn.close
  rescue Exception => e
    logger.fatal e
  ensure
  end
end

def classify(str)
  str.split(/[_-]/).collect(&:capitalize).join
end


class TaskQueueServer < ::Servolux::Server

  include Logging

  # Create a preforking server that has the given minimum and
  # maximum boundaries
  #
  def initialize( min_workers = 2, max_workers = 10 )
    super( self.class.name, :interval => 60, :logger => logger )
    logger.debug "TaskQueueServer logger id: #{logger.__id__}"
    # Create our preforking worker pool. Each worker will run the
    # code found in the JobProcessor module. We set a timeout of 10
    # minutes. The child process must send a "heartbeat" message to
    # the parent within this timeout period; otherwise, the parent
    # will halt the child process.
    #
    # Our execute code in the JobProcessor takes this into account.
    # It will wakeup every 2 minutes, if no jobs are reserved from
    # the RabbitMQ queue, and send the heartbeat message.
    #
    # This also means that if any job processed by a worker takes
    # longer than 10 minutes to run, that child worker will be
    # killed.
    @pool = Servolux::Prefork.new( :module => JobProcessor, :timeout => 600,
                                   :min_workers => min_workers, :max_workers => max_workers )
  end

  def log( msg )
    logger.info msg
  end

  def log_pool_status
    log "Pool status : #{@pool.worker_counts.inspect} living pids #{live_worker_pids.join(' ')}"
  end

  def live_worker_pids
    pids = []
    @pool.each_worker { |w| pids << w.pid if w.alive? }
    return pids
  end

  def shutdown_workers
    log "Shutting down all workers"
    @pool.stop
    loop do
      log_pool_status
      break if @pool.live_worker_count <= 0
      sleep 0.25
    end
  end

  def log_worker_status( worker )
    if not worker.alive? then
      worker.wait
      if worker.error then
        log "Worker #{worker.pid} child error: #{worker.error.inspect}"
      elsif worker.exited? then
        log "Worker #{worker.pid} exited with status #{worker.exitstatus}"
      elsif worker.signaled? then
        log "Worker #{worker.pid} signaled by #{worker.termsig}"
      elsif worker.stopped? then
        log "Worker #{worker.pid} stopped by #{worker.stopsig}"
      else
        log "I have no clue #{worker.inspect}"
      end
    end
  end

  #############################################################################
  # Implementations of parts of the Servolux::Server API
  #############################################################################

  # this is run once before the Server's run loop
  def before_starting
    log "Starting up the Pool"
    # Start up child processes to handle jobs
    num_workers = ((@pool.min_workers + @pool.max_workers) / 2).round
    @pool.start( num_workers )
    log "Send a USR1 to add a worker                        (kill -usr1 #{Process.pid})"
    log "Send a USR2 to kill all the workers                (kill -usr2 #{Process.pid})"
    log "Send a INT (Ctrl-C) or TERM to shutdown the server (kill -term #{Process.pid})"
  end

  # Add a worker to the pool when USR1 is received
  def usr1
    log "Adding a worker"
    @pool.add_workers
  end

  # kill all the current workers with a usr2, the run loop will respawn up to
  # the min_worker count
  #
  def usr2
    shutdown_workers
  end

  # By default, Servolux::Server will capture the TERM signal and call its
  # +shutdown+ method. After that +shutdown+ method is called it will call
  # +after_shutdown+ we're going to hook into that so that all the workers get
  # cleanly shutdown before the parent process exits
  def after_stopping
    shutdown_workers
  end

  # This is the method that is executed during the run loop
  #
  def run
    log_pool_status
    @pool.each_worker do |worker|
      log_worker_status( worker )
    end
    @pool.ensure_worker_pool_size
  end
end


$mqhost = ARGV[0] || "localhost"

tqs = TaskQueueServer.new
tqs.startup


# vim: et:
