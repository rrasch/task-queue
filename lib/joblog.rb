#!/usr/bin/env ruby

require 'json'
require 'mysql2'
require 'sql-maker'

class JobLog

  def initialize(config_file, logger)
    @client = Mysql2::Client.new(
      :default_file  => config_file,
      :read_timeout => 30,
      :write_timeout => 60,
      :connect_timeout => 10,
      :reconnect => true,
    )
    @logger = logger
  end

  def select_job(args)
    stmt = SQL::Maker::Select.new(:auto_bind => true)
                                  .add_select('*')
                                  .add_from('job')
    if args.key?(:batch_id)
      stmt.add_where('batch_id' => args[:batch_id])
    end
    if args.key?(:from)
      stmt.add_where('submitted' => {'>' => args[:from]})
    end
    if args.key?(:to)
      stmt.add_where('submitted' => {'<' => args[:to]})
    end
    if args.key?(:limit)
      stmt.limit(args[:limit])
    end
    @logger.debug("Executing #{stmt.as_sql}")
    result = @client.query(stmt.as_sql)
  end

  def update_job(task, create=true)
    result = nil
    if task['job_id'].nil? && create
      @logger.debug "Inserting job into batch_id=#{task['batch_id']}"
      insert_job = @client.prepare(
       "INSERT INTO job
        (batch_id, state, request, user_id, worker_host, started, completed)
        VALUES (?, ?, ?, ?, ?, ?, ?)")
      result = insert_job.execute(
        task['batch_id'],
        task['state'], JSON.generate(task),
        task['user_id'], task['worker_host'],
        task['started'], task['completed'])
      task['job_id'] = @client.last_id
      @logger.debug "Created job_id=#{task['job_id']}"
    else
      @logger.debug "Updating job_id=#{task['job_id']}"
      update_job = @client.prepare(
       "UPDATE job
        SET state = ?, worker_host = ?, started = ?, completed = ?
        WHERE job_id = ?")
      result = update_job.execute(
        task['state'], task['worker_host'],
        task['started'], task['completed'],
        task['job_id'])
      @logger.debug "Updated job_id=#{task['job_id']}"
    end
    return result
  end

  def close
    @client.close
  end

end
