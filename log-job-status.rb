#!/usr/bin/env ruby

require 'rubygems'
require 'bunny'
require 'json'
require 'mysql2'
require 'optparse'
require './lib/tasklog'

# Set default options
options = {
  :mqhost    => "localhost",
  :my_cnf    => "/content/prod/rstar/etc/my-taskqueue.cnf",
  :logfile   => Dir.pwd + "/log-job-status.log",
  :daemonize => false,
  :verbose   => false,
}


def find_coll_type(rstar_dir, wip_id)
  data_dir = "#{rstar_dir}/wip/se/#{wip_id}/data"
  if !Dir["#{data_dir}/*_d.mov"].empty?
    'video'
  elsif !Dir["#{data_dir}/*_mods.xml"].empty?
    'book'
  else
    'photo'
  end
end


OptionParser.new do |opts|

  opts.banner = "Usage: #{$0} [options]"
  
  opts.on('-m', '--mqhost MQHOST', 'RabbitMQ Host') do |m|
    options[:mqhost] = m
  end

  opts.on('-l', '--logfile LOGFILE', 'Log file') do |l|
    options[:logfile] = l
  end

  opts.on('-c', '--my-cnf CONFIG FILE', 'MySQL config for taskqueue db') do |c|
    options[:my_cnf] = c
  end

  opts.on('-d', '--daemonize', 'Daemonize process') do
    options[:daemonize] = true
  end

  opts.on('-v', '--verbose', 'Enable debugging messages') do
    options[:verbose] = true
  end

  opts.on('-h', '--help', 'Print help message') do
    puts opts
    exit
  end

end.parse!

logfile = File.new(options[:logfile], 'a')
logfile.sync = true
logger = Logger.new(logfile, 5, 1000000)
logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO

if options[:daemonize]
  logger.debug "Putting process #{Process.pid} in background"
  Process.daemon
end

$stdout = logfile
$stderr = logfile

logger.debug "Lowering priority of process #{Process.pid}"
Process.setpriority(Process::PRIO_PROCESS, 0, 19)

conn = Bunny.new(:host   => options[:mqhost],
                 :logger => logger)
conn.start

ch = conn.create_channel
x = ch.topic("tq_logging", :auto_delete => true)
q = ch.queue("tq_log_reader", :durable => true)
q.bind(x, :routing_key => "task_queue.*")

consumer = nil

begin
  q.subscribe(:block => true,
              :manual_ack => true) do |delivery_info, properties, payload|
    begin
      consumer = delivery_info[:consumer]

      logger.debug "Received #{payload}, "\
                   "message proprties are #{properties.inspect}, and "\
                   "delivery info is #{delivery_info.inspect}"

      task = JSON.parse(payload)

      # parse rstar_dir to get provider and collection value
      # e.g. /content/prod/rstar/content/nyu/aco/
      # provider = 'nyu', collection = 'aco'
      rstar_dir = task['rstar_dir']
      dirname, collection = File.split(rstar_dir)
      provider = File.basename(dirname)
      logger.debug "provider: #{provider}, collection: #{collection}"

      wip_id =  task['identifiers'][0]
      logger.debug "wip_id: #{wip_id}"

      coll_type = find_coll_type(rstar_dir, wip_id)

      tasklog = TaskLog.new(options[:my_cnf], logger)
      collection_id = tasklog.collection(provider, collection, coll_type)
      logger.debug "collection_id: #{collection_id}"
      tasklog.update(collection_id, wip_id, task)
      tasklog.close

      ch.ack(delivery_info.delivery_tag)
    rescue Exception => e
      logger.error e
      consumer.cancel if consumer
    end
  end
rescue SignalException => e
  logger.info "Process #{Process.pid} received signal #{e} (#{e.signo})"
rescue Exception => e
  logger.error e
end

