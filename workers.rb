#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Preforking RabbitMQ job runner using Servolux.
#
# On startup the server forks a pool of worker processes. Each worker
# connects to the RabbitMQ queue named task_queue, waits for jobs,
# and processes them as they arrive.

require 'rubygems'
require 'bunny'
require 'etc'
require 'json'
require 'logger'
require 'optparse'
require 'servolux'
require_relative './lib/exceptions'
require_relative './lib/helpers'
require_relative './lib/task'
require_relative './lib/tqcommon'

# JobProcessor defines methods executed by each worker
module JobProcessor
  # Open a connection to our RabbitMQ queue. This method is called once just
  # before entering the child run loop.
  def before_executing # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    @logger = config[:logger]
    @logger.debug 'entering JobProcessor.before_executing()'
    begin
      @logger.debug "Connecting to #{config[:mqhost]}"
      @conn = Bunny.new(
        host: config[:mqhost],
        automatically_recover: true,
        logger: @logger
      )
      @conn.start
      @ch = @conn.create_channel
      @q = @ch.queue('task_queue',
                     durable: true,
                     arguments: { 'x-max-priority' => 10 })
      @ch.prefetch(1)
      @x = @ch.topic('tq_logging', durable: true, auto_delete: false)
      @logger.debug 'Connected.'
    rescue Bunny::TCPConnectionFailed => e
      @logger.error "Connection to #{config[:mqhost]} failed - #{e}"
      raise
    rescue StandardError => e
      @logger.error e
      raise
    end
  end

  # Close the connection to our RabbitMQ queue. This method is called once
  # just after the child run loop stops and just before the child exits.
  def after_executing
    @logger.debug 'entering JobProcessor.after_executing()'
    @conn.close
  end

  # Close the RabbitMQ socket when we receive SIGTERM. This allows the execute
  # thread to return processing back to the child run loop; the child run loop
  # will gracefully shutdown the process.
  def term
    @conn.close
    @thread.wakeup
  end

  # Process jobs from RabbitMQ
  def execute # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    @logger.debug 'entering JobProcessor.execute()'
    @q.subscribe(manual_ack: true, block: true) do |delivery_info, _props, body|
      @logger.debug "[x] Received '#{body}'"
      task = Task.new(body: body,
                      logger: @logger,
                      channel: @ch,
                      exchange: @x,
                      delivery_tag: delivery_info.delivery_tag,
                      services: @config[:svc_lookup])
      @logger.debug "task: #{task}"
      task.process
    rescue StandardError => e
      #raise
      is_invalid_err = e.is_a?(InvalidTaskError)
      err_msg = is_invalid_err ? e.message : e.full_message
      task.mark_error(e, err_msg)
      @conn.close unless is_invalid_err
    end
  rescue StandardError => e
    @logger.error "execute error #{e.full_message}"
    @conn.close
    raise
  end
end

# The TaskQueueServer class provides a pre-forking worker pool for
# executing tasks in parallel using multiple processes.
class TaskQueueServer < Servolux::Server
  # Create a preforking server that has the given minimum and
  # maximum boundaries
  #
  def initialize(config)
    super(self.class.name, config)

    # Create our preforking worker pool. Each worker will run the
    # code found in the JobProcessor module.
    @pool = Servolux::Prefork.new(
      module: JobProcessor,
      config: config,
      min_workers: config[:min_workers],
      max_workers: config[:max_workers]
    )
  end

  def log(msg)
    @logger.info msg
  end

  def log_pool_status
    @logger.debug "Pool status: #{@pool.worker_counts.inspect} " \
                  "living pids #{live_worker_pids.join(' ')}"
  end

  def live_worker_pids
    pids = []
    @pool.each_worker { |w| pids << w.pid if w.alive? }
    pids
  end

  def shutdown_workers
    log 'Shutting down all workers'
    @pool.stop
    loop do
      log_pool_status
      break if @pool.live_worker_count <= 0

      sleep 0.25
    end
  end

  def remove_worker
    workers = []
    @pool.each_worker { |w| workers << w if w.alive? }
    return unless workers.size > @pool.min_workers

    retiring_worker = workers.last
    retiring_worker.stop
    sleep 0.5
    retiring_worker.reap
  end

  def log_worker_status(worker)
    return if worker.alive?

    worker.wait
    log worker_status_message(worker)
  end

  def worker_status_message(worker) # rubocop:disable Metrics/MethodLength
    if worker.error
      "Worker #{worker.pid} child error: #{worker.error.inspect}"
    elsif worker.exited?
      "Worker #{worker.pid} exited with status #{worker.exitstatus}"
    elsif worker.signaled?
      "Worker #{worker.pid} signaled by #{worker.termsig}"
    elsif worker.stopped?
      "Worker #{worker.pid} stopped by #{worker.stopsig}"
    else
      "I have no clue #{worker.inspect}"
    end
  end

  #############################################################################
  # Implementations of parts of the Servolux::Server API
  #############################################################################

  # this is run once before the Server's run loop
  def before_starting
    # Start up child processes to handle jobs.
    log "Starting up the pool of #{@pool.max_workers} workers"
    @pool.start(@pool.max_workers)
    log 'Send a USR1 to add a worker                        ' \
        "(kill -usr1 #{Process.pid})"
    log 'Send a USR2 to kill all the workers                ' \
        "(kill -usr2 #{Process.pid})"
    log 'Send a INT (Ctrl-C) or TERM to shutdown the server ' \
        "(kill -term #{Process.pid})"
    log 'Send a HUP to reopen log file                      ' \
        "(kill -hup #{Process.pid})"
  end

  # Add a worker to the pool when USR1 is received
  def usr1
    log 'Adding a worker'
    @pool.add_workers
  end

  # Remove a worker from the pool when USR2 is received
  def usr2
    log 'Removing a worker'
    remove_worker
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
  def run
    log_pool_status
    @pool.each_worker do |worker|
      log_worker_status(worker)
    end
    @pool.ensure_worker_pool_size
  end
end

# Start

# Max number of workers is number of cpus - 1
# or 1 if there is only 1 cpu
max_workers = [1, Etc.nprocessors - 1].max

config = {
  mqhost:      'localhost',
  interval:    120,
  logfile:     "#{Dir.pwd}/worker.log",
  pidfile:     "#{Dir.pwd}/taskqueueserver.pid",
  log_level:   Logger::INFO,
  foreground:  false,
  min_workers: 1,
  max_workers: max_workers,
  svc_lookup:  TQCommon.services.map { |svc| [svc, true] }.to_h
}

log_levels = {
  'debug' => Logger::DEBUG,
  'info'  => Logger::INFO,
  'warn'  => Logger::WARN,
  'error' => Logger::ERROR,
  'fatal' => Logger::FATAL
}

OptionParser.new do |opts| # rubocop:disable Metrics/BlockLength
  opts.banner = 'Usage: workers.rb [options]'

  opts.on('-m', '--mqhost MQHOST', 'RabbitMQ Host') do |m|
    config[:mqhost] = m
  end

  opts.on('-i', '--interval INTERVAL', 'Run loop interval') do |i|
    config[:interval] = i
  end

  opts.on('-l', '--logfile LOGFILE', 'Log output here') do |l|
    config[:logfile] = l
  end

  opts.on('-p', '--pidfile PIDFILE', 'Pid file') do |p|
    config[:pid_file] = p
  end

  opts.on('-f', '--foreground', 'Stay in the foreground') do
    config[:foreground] = true
  end

  opts.on('-L', '--log-level LEVEL', log_levels.keys,
          "Set log level (#{log_levels.keys.join(', ')})") do |level|
    config[:log_level] = log_levels[level]
  end

  opts.on('-n', '--min-workers MIN_WORKERS', Integer,
          'Min number of workers') do |n|
    config[:min_workers] = n
  end

  opts.on('-x', '--max-workers MAX_WORKERS', Integer,
          'Max number of workers') do |x|
    config[:max_workers] = x
  end

  opts.on('-h', '--help', 'Print help message') do
    puts opts
    exit
  end
end.parse!

if config[:max_workers] < config[:min_workers]
  abort("Max workers (#{config[:max_workers]}) must " \
        "be greater than min workers (#{config[:min_workers]})")
end

config[:logfh] = File.new(config[:logfile], 'a')
config[:logfh].sync = true

Process.daemon unless config[:foreground]

$stdout = config[:logfh]
$stderr = config[:logfh]
config[:logger] = Logger.new(config[:logfh])
config[:logger].level = config[:log_level]

config[:logger].debug beautify(config)

ENV['TQ_SERVER_PID'] = Process.pid.to_s

tqs = TaskQueueServer.new(config)
tqs.startup
