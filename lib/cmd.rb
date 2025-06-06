require 'open3'
require 'shellwords'

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
      if !@args['rstar_dir'].nil? && script_name !~ / -r /
        cmd = "#{@bin_dir}/#{script_name} -q -r #{@args['rstar_dir']} "\
              "#{@args['extra_args']} "\
              "#{@args['identifiers'].join(' ')}"
      else
        cmd = "#{script_name}"
      end
      env = @args.fetch('env', {})
      cmd_list = Shellwords.split(cmd)
      @logger.debug("Executing '#{cmd}' with env #{env}")
      @logger.debug("Cmd list: #{cmd_list}")
      begin
        output, status = Open3.capture2e(env, *cmd_list)
        success = status.exitstatus.zero?
      rescue SystemCallError => e
        output = "Failed to execute '#{cmd}': #{e.class} #{e.message}"
        success = false
      end
      total_output.concat(output)
      if success
        @logger.debug output
      else
        @logger.error output
        break
      end
    end
    return {
      :success => success,
      :output  => total_output,
    }
  end

  def self.do_or_die(cmd, logger)
    cmd_list = Shellwords.split(cmd)
    logger.debug "Running '#{cmd}'"
    logger.debug("Cmd list: #{cmd_list}")
    output, status = Open3.capture2e(*cmd_list)
    logger.debug output
    if ! status.exitstatus.zero?
      logger.error "#{cmd} exited with status #{status.exitstatus}"
      exit 1
    end
    return output
  end

end
