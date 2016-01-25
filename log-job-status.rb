#!/usr/bin/env ruby

require 'rubygems'
require 'bunny'
require 'json'
require 'mysql2'
require 'optparse'

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

client = Mysql2::Client.new(
  :default_file  => options[:my_cnf],
  :connect_timeout => 5,
)

# XXX: create a library for db statemets
insert_col = client.prepare(
 "INSERT INTO collection
  (collection_id, provider, collection, type)
  VALUES
  (0, ?, ?, ?)")

select_col = client.prepare(
 "SELECT collection_id FROM collection
  WHERE provider = ? AND collection = ?")

insert_log = client.prepare(
 "INSERT INTO task_queue_log
  (collection_id, wip_id, state, user_id, worker_host, started, completed)
  VALUES 
  (?, ?, ?, ?, ?, ?, ?)")

update_log = client.prepare(
 "UPDATE task_queue_log
  SET state = ?, user_id = ?, worker_host = ?, started = ?, completed = ?
  WHERE collection_id = ? AND wip_id = ?")

select_log = client.prepare(
 "SELECT t.completed FROM task_queue_log t, collection c
  WHERE t.collection_id = c.collection_id
  AND t.collection_id = ? and t.wip_id = ?")

conn = Bunny.new(:host   => options[:mqhost],
                 :logger => logger)
conn.start

ch = conn.create_channel
x = ch.topic("tq_logging", :auto_delete => true)
q = ch.queue("tq_log_reader", :durable => true)
q.bind(x, :routing_key => "task_queue.*")

consumer = nil

begin
  q.subscribe(:block => true, :manual_ack => true) do |delivery_info, properties, payload|
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

      user_id = task['user_id'] || 'unknown'

      # Get collection id. Add it to table if it doesn't exist
      results = select_col.execute(provider, collection)
      if results.count == 0
        coll_type = find_coll_type(rstar_dir, wip_id)
        insert_col.execute(provider, collection, coll_type)
        collection_id = client.last_id
      else
        collection_id = results.first['collection_id']
      end
      logger.debug "collection_id: #{collection_id}"

      results = select_log.execute(collection_id, wip_id)
      if results.count == 0
        logger.debug "Inserting into log for #{wip_id}"
        insert_log.execute(
          collection_id, wip_id,
          task['state'], user_id, task['worker_host'],
          task['started'], task['completed'])
      else
        logger.debug "Updating log for #{wip_id}"
        update_log.execute(
          task['state'], user_id, task['worker_host'],
          task['started'], task['completed'],
          collection_id, wip_id)
      end
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

