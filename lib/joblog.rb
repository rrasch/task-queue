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

  def select_batch(batch_id)
    @logger.debug "batch id: #{batch_id}"
    query = SQL::Maker::Select.new.add_select('*')
                                  .add_from('batch')
                                  .add_where('batch_id' => batch_id)
    @logger.debug "sql: #{query.as_sql}"
    @logger.debug "bind value: #{query.bind}"
    stmt = @client.prepare(query.as_sql)
    result = stmt.execute(*(query.bind))
    result.first
  end

  def select_job(args)
    @logger.debug "entering select_job(#{args})"
    subquery = SQL::Maker::Select.new.add_select('*').add_from('job')
    if args.key?(:batch_id)
      subquery.add_where('batch_id' => args[:batch_id])
    end
    if args.key?(:from)
      @logger.debug "starting date: #{args[:from]}"
      subquery.add_where('submitted' => {'>=' => args[:from]})
    end
    if args.key?(:to)
      @logger.debug "ending date: #{args[:to]}"
      subquery.add_where('submitted' => {'<=' => args[:to]})
    end
    subquery.add_order_by('job_id' => 'DESC')
    if args.key?(:limit)
      subquery.limit(args[:limit])
    end
    query = SQL::Maker::Select.new.add_select('*')
                                  .add_from(subquery => 'job_table')
                                  .add_order_by('job_id' => 'ASC')
    @logger.debug "sql: #{query.as_sql}"
    @logger.debug "bind values: #{query.bind}"
    stmt = @client.prepare(query.as_sql)
    result = stmt.execute(*(query.bind))
  end

  def update_job(task, create=true)
    result = nil
    output = task['output']
    if output.to_s.strip.empty?
      output = nil
    end
    if task['job_id'].nil? && create
      @logger.debug "Inserting job into batch_id=#{task['batch_id']}"
      insert_job = @client.prepare(
       "INSERT INTO job (
        batch_id, state,
        output, request,
        user_id, worker_host,
        started, completed)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
      result = insert_job.execute(
        task['batch_id'], task['state'],
        output, JSON.generate(task),
        task['user_id'], task['worker_host'],
        task['started'], task['completed'])
      task['job_id'] = @client.last_id
      @logger.debug "Created job_id=#{task['job_id']}"
    else
      @logger.debug "Updating job_id=#{task['job_id']}"
      update_job = @client.prepare(
       "UPDATE job
        SET state = ?, output = ?,
        worker_host = ?, started = ?,
        completed = ?
        WHERE job_id = ?")
      result = update_job.execute(
        task['state'], output,
        task['worker_host'], task['started'],
        task['completed'],
        task['job_id'])
      @logger.debug "Updated job_id=#{task['job_id']}"
    end
    num_rows = @client.affected_rows
    @logger.debug "Query updated #{num_rows} rows."
    return num_rows
  end

  def close
    @client.close
  end

end
