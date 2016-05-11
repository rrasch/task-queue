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
require 'optparse'
require 'servolux'
require 'socket'
require_relative './lib/audio'
require_relative './lib/bagit'
require_relative './lib/book_publisher'
require_relative './lib/video'

module JobProcessor

  # Open a connection to our RabbitMQ queue. This method is called once just
  # before entering the child run loop.
  def before_executing
    @logger = config[:logger]
    @logger.debug "JobProcessor logger id: #{@logger.__id__}"
    @logger.debug "entering JobProcessor.before_executing()"
    begin
      @logger.debug "Connecting to #{config[:mqhost]}"
      @conn = Bunny.new(
        :host => config[:mqhost],
        :automatically_recover => true,
        :logger => @logger
      )
      @conn.start
      @ch = @conn.create_channel
      @q = @ch.queue("task_queue",
        :durable => true,
        :arguments => {"x-max-priority" => 10}
      )
      @ch.prefetch(1)
      @x = @ch.topic("tq_logging", :auto_delete => true)
      @logger.debug "Connected."
    rescue Bunny::TCPConnectionFailed => e
      @logger.error "Connection to #{config[:mqhost]} failed - #{e}"
      raise e
    rescue Exception => e
      @logger.error e
      raise e
    end
  end

  # Close the connection to our RabbitMQ queue. This method is called once
  # just after the child run loop stops and just before the child exits.
  def after_executing
    @logger.debug "entering JobProcessor.after_executing()"
    @conn.close
  end

  # Close the RabbitMQ socket when we receive SIGTERM. This allows the execute
  # thread to return processing back to the child run loop; the child run loop
  # will gracefully shutdown the process.
  def term
    @conn.close
    @thread.wakeup
  end

  # Reserve a job from the RabbitMQ queue, and processes jobs as we receive
  # them. We have a timeout set for 2 minutes so that we can send a heartbeat
  # back to the parent process even if the RabbitMQ queue is empty.
  #
  # This method is called repeatedly by the child run loop until the child is
  # killed via SIGHUP or SIGTERM or halted by the parent.
  def execute
    @logger.debug "entering JobProcessor.execute()"
    @q.subscribe(:manual_ack => true, :block => true) do |delivery_info, properties, body|
      begin
        @logger.debug " [x] Received '#{body}'"
        task = JSON.parse(body)
        @logger.debug task.inspect
        task['logger'] = @logger
        task['state'] = "processing"
        #task['worker_host'] = Socket.gethostname[/^[^.]+/]
        task['worker_host'] = get_ip_addr
        task['started'] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        @x.publish(JSON.pretty_generate(task),
                   :routing_key => "task_queue.processing")
        class_name = classify(task['class'])
        @logger.debug "Creating new #{class_name} object"
        obj = Object::const_get(class_name).new(task)
        method_name = task['operation'].tr('-', '_')
        @logger.debug "Executing #{method_name}"
        status = obj.send(method_name)
        if status[:success] then
          state = "success"
        else
          state = "error"
        end
        @logger.debug "#{state.capitalize}!"
        @logger.debug " [x] Done"
        task['state'] = state
        task['completed'] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        @logger.debug "Publishing to task_queue.#{state}"
        @x.publish(JSON.pretty_generate(task),
                   :routing_key => "task_queue.#{state}")
        @logger.debug "Sending ack"
        @ch.ack(delivery_info.delivery_tag)
      rescue Exception => e
        @logger.error e
        @conn.close
      end
    end
  rescue Exception => e
    @logger.error e
    @conn.close
    raise e
  end
end

def classify(str)
  str.split(/[_-]/).collect(&:capitalize).join
end

def get_ip_addr
  Socket.ip_address_list.detect{|ip|
    ip.ipv4? and !ip.ipv4_loopback? and !ip.ipv4_multicast?}.ip_address
end

class TaskQueueServer < ::Servolux::Server

  # Create a preforking server that has the given minimum and
  # maximum boundaries
  #
  def initialize(min_workers, max_workers, config)

    @config = config
    @logger = config[:logger]

    super(self.class.name, :interval => 120, :logger => @logger,
      :pid_file => config[:pidfile])

    @logger.debug "TaskQueueServer logger id: #{@logger.__id__}"

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
    @pool = Servolux::Prefork.new(
      :module => JobProcessor,
      :timeout => config[:timeout],
      :config => config,
      :min_workers => min_workers,
      :max_workers => max_workers
    )
  end

  def log(msg)
    @logger.info msg
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

  def log_worker_status(worker)
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
    # Start up child processes to handle jobs
    num_workers = ((@pool.min_workers.to_f + @pool.max_workers) / 2).round
    log "Starting up the pool of #{num_workers} workers"
    @pool.start(num_workers)
    log "Send a USR1 to add a worker                        (kill -usr1 #{Process.pid})"
    log "Send a USR2 to kill all the workers                (kill -usr2 #{Process.pid})"
    log "Send a INT (Ctrl-C) or TERM to shutdown the server (kill -term #{Process.pid})"
    log "Send a HUP to reopen log file                      (kill -hup #{Process.pid})"
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

  def hup
    @config[:logfh].reopen(@config[:logfile], 'a')
    @config[:logfh].sync = true
    @logger.info "Reopened log file #{@config[:logfile]}"
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
      log_worker_status(worker)
    end
    @pool.ensure_worker_pool_size
  end
end


# Start

config = {
  :mqhost  => "localhost",
  :timeout => nil,
  :logfile => Dir.pwd + "/worker.log",
  :pidfile => Dir.pwd + "/taskqueueserver.pid",
  :quiet   => false,
}

# puts config[:logfile]
# puts config[:pidfile]

OptionParser.new do |opts|

  opts.banner = "Usage: workers.rb [options]"

  opts.on('-m', '--mqhost MQHOST', 'RabbitMQ Host') do |h|
    config[:mqhost] = h
  end

  opts.on('-t', '--timeout PORT', 'Worker timeout') do |t|
    config[:timeout] = t
  end

  opts.on('-l', '--logfile LOGFILE', 'Log output here') do |l|
    config[:logfile] = l
  end

  opts.on('-p', '--pidfile PIDFILE', 'Pid file') do |l|
    config[:pidfile] = p
  end

  opts.on('-q', '--quiet', 'Suppress debugging messages') do
    config[:quiet] = true
  end

  opts.on('-h', '--help', 'Print help message') do
    puts opts
    exit
  end

end.parse!

config[:logfh] = File.new(config[:logfile], 'a')
config[:logfh].sync = true

Process.daemon

$stdout = config[:logfh]
$stderr = config[:logfh]
config[:logger] = ::Logger.new(config[:logfh])
if config[:quiet]
  config[:logger].level = Logger::INFO
end


tqs = TaskQueueServer.new(3, 10, config)
tqs.startup

# vim: et:
