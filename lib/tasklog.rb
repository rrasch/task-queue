#!/usr/bin/env ruby

require 'mysql2'

class TaskLog

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

  def collection(provider, collection, coll_type, create=true)
    collection_id = nil

    select_col = @client.prepare(
     "SELECT collection_id FROM collection
      WHERE provider = ? AND collection = ?")

    insert_col = @client.prepare(
     "INSERT INTO collection
      (collection_id, provider, collection, type)
      VALUES
      (0, ?, ?, ?)")

    results = select_col.execute(provider, collection)
    if results.count == 0
      coll_type = find_coll_type(rstar_dir, wip_id)
      insert_col.execute(provider, collection, coll_type)
      collection_id = @client.last_id
    elsif create
      collection_id = results.first['collection_id']
    end

    return collection_id
  end


  def update(collection_id, wip_id, task)
    select_log = @client.prepare(
     "SELECT t.collection_id FROM task_queue_log t, collection c
      WHERE t.collection_id = c.collection_id
      AND t.collection_id = ? and t.wip_id = ?")

    insert_log = @client.prepare(
     "INSERT INTO task_queue_log
      (collection_id, wip_id, state, user_id, worker_host, started, completed)
      VALUES 
      (?, ?, ?, ?, ?, ?, ?)")
    
    update_log = @client.prepare(
     "UPDATE task_queue_log
      SET state = ?, user_id = ?, worker_host = ?, started = ?, completed = ?
      WHERE collection_id = ? AND wip_id = ?")
   
    results = select_log.execute(collection_id, wip_id)
    if results.count == 0
      @logger.debug "Inserting into log for #{wip_id}"
      insert_log.execute(
        collection_id, wip_id,
        task['state'], task['user_id'], task['worker_host'],
        task['started'], task['completed'])
    else
      @logger.debug "Updating log for #{wip_id}"
      update_log.execute(
        task['state'], task['user_id'], task['worker_host'],
        task['started'], task['completed'],
        collection_id, wip_id)
    end
  end

  def close
    @client.close
  end

end
