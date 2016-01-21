#!/usr/bin/env ruby

require 'open3'

class Cmd

  def initialize(rstar_dir, ids, logger, bin_dir = '/usr/bin')
    @rstar_dir = rstar_dir
    @ids = ids
    @logger = logger
    @bin_dir = bin_dir
  end

  def do_cmd(*script_names)
    total_output = ""
    success = true
    script_names.each do |script_name|
      if !@rstar_dir.nil?
        cmd = "#{@bin_dir}/#{script_name} -q -r #{@rstar_dir} "\
              "#{@ids.join(' ')}"
      else
        cmd = "#{script_name}"
      end
      output, status = Open3.capture2e(cmd)
      @logger.debug output
      total_output.concat(output)
      success = status.exitstatus.zero?
      break if !success
    end
    return {
      :success => success,
      :output  => total_output,
    }
  end

  def self.get_cmd(logger)
    self.new(nil, nil, logger, nil)
  end

  def self.do_or_die(cmd, logger)
    logger.debug "Running '#{cmd}'"
    output, status = Open3.capture2e(cmd)
    logger.debug output
    if ! status.exitstatus.zero?
      logger.error "#{cmd} exited with status #{status.exitstatus}"
      exit 1
    end
    return output
  end

end

