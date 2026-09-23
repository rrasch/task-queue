# frozen_string_literal: true

require 'json'
require 'mysql2'
require 'sql-maker'

# JobLog is a class to query and update the job log table
# in the task queue MySQL database
class JobLog # rubocop:disable Metrics/ClassLength
  def initialize(config_file, logger)
    @client = Mysql2::Client.new(
      default_file: config_file,
      read_timeout: 30,
      write_timeout: 60,
      connect_timeout: 10
    )
    @logger = logger
  end

  def select_batch(batch_id)
    @logger.debug "batch id: #{batch_id}"
    query = SQL::Maker::Select.new.add_select('*').add_from('batch')
    if batch_id.is_a?(Array)
      query.add_where('batch_id' => { between: batch_id })
    else
      query.add_where('batch_id' => batch_id)
    end
    do_query(query)
  end

  def select_job(args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    @logger.debug "entering select_job(#{args})"
    subquery = SQL::Maker::Select.new.add_select('*').add_from('job')
    if args.key?(:batch_id)
      if args[:batch_id].is_a?(Array)
        subquery.add_where('batch_id' => { between: args[:batch_id] })
      else
        subquery.add_where('batch_id' => args[:batch_id])
      end
    end
    if args.key?(:from)
      @logger.debug "starting date: #{args[:from]}"
      subquery.add_where('submitted' => { '>=' => args[:from] })
    end
    if args.key?(:to)
      @logger.debug "ending date: #{args[:to]}"
      subquery.add_where('submitted' => { '<=' => args[:to] })
    end
    subquery.add_order_by('job_id' => 'DESC')
    subquery.limit(args[:limit].to_s) if args.key?(:limit)
    query = SQL::Maker::Select.new.add_select('*')
                              .add_from(subquery => 'job_table')
                              .add_order_by('job_id' => 'ASC')
    do_query(query)
  end

  def state_counts(args)
    @logger.debug "entering state_counts(#{args})"
    query = SQL::Maker::Select.new
    query.add_select('state')
         .add_select(SQL::QueryMaker.sql_raw('COUNT(*)') => 'count')
         .add_from('job')
         .add_where('batch_id' => { between: args[:batch_id] })
         .add_group_by('state')
    do_query(query)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def update_job(task, create: true)
    output = task['output']
    if output.to_s.strip.empty?
      output = nil
    else
      max_field_size_in_bytes = 65_535
      output = output[0, max_field_size_in_bytes]
    end
    if task['job_id'].nil? && create
      @logger.debug "Inserting job into batch_id=#{task['batch_id']}"
      insert_job = @client.prepare(
        "INSERT INTO job (
        batch_id, state,
        output, request,
        user_id, worker_host,
        started, completed)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
      )
      insert_job.execute(
        task['batch_id'], task['state'],
        output, JSON.generate(task),
        task['user_id'], task['worker_host'],
        task['started'], task['completed']
      )
      task['job_id'] = @client.last_id
      @logger.debug "Created job_id=#{task['job_id']}"
    else
      @logger.debug "Updating job_id=#{task['job_id']}"
      update_job = @client.prepare(
        "UPDATE job
        SET state = ?, output = ?,
        worker_host = ?, started = ?,
        completed = ?
        WHERE job_id = ?"
      )
      update_job.execute(
        task['state'], output,
        task['worker_host'], task['started'],
        task['completed'],
        task['job_id']
      )
      @logger.debug "Updated job_id=#{task['job_id']}"
    end
    num_rows = @client.affected_rows
    @logger.debug "Query updated #{num_rows} rows."
    num_rows
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def close
    @client.close
  end

  private

  def do_query(query)
    @logger.debug "sql: #{query.as_sql}"
    @logger.debug "bind values: #{query.bind}"
    stmt = @client.prepare(query.as_sql)
    stmt.execute(*query.bind)
  end
end
