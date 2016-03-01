#!/usr/bin/env ruby

require 'open3'

class Cmd

  BIN_DIR = '/usr/bin'

  def initialize(args)
    @args    = args.clone
    @logger  = @args['logger']
    @bin_dir = @args['bin_dir'] || BIN_DIR
  end

  def do_cmd(*script_names)
    total_output = ""
    success = true
    script_names.each do |script_name|
      if @args['add_rstar'] == true
        cmd = "#{@bin_dir}/#{script_name} -q -r #{@args['rstar_dir']} "\
              "#{@args['identifiers'].join(' ')}"
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

