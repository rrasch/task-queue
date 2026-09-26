# frozen_string_literal: true

require 'open3'
require 'shellwords'
require_relative './tqcommon'

# Cmd is a class to execute commands
class Cmd
  BIN_DIR = '/usr/bin'

  def initialize(args, logger)
    @args    = args.dup
    @logger  = logger
    @bin_dir = @args['bin_dir'] || BIN_DIR
  end

  def [](key)
    @args[key]
  end

  def []=(key, value)
    @args[key] = value
  end

  def do_cmd(*cmd_list) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    total_output = String.new
    success = true
    cmd_list.each do |cmd| # rubocop:disable Metrics/BlockLength
      prog, *args = cmd

      final_cmd = cmd
      if needs_rstar_arg(cmd)
        final_cmd = ["#{@bin_dir}/#{prog}",
                     *args,
                     '-q',
                     '-r', @args['rstar_dir'],
                     *@args['extra_args'].shellsplit,
                     *@args['identifiers']]
      end

      env = @args.fetch('env', {}).dup
      env['TMPDIR'] ||= TQCommon.tmpdir

      @logger.debug("Cmd: #{final_cmd}")
      @logger.info("Executing [#{final_cmd.shelljoin}] with env #{env}")

      begin
        output, status = self.class.capture(env, final_cmd)
        success = status.exitstatus.zero?
      rescue SystemCallError => e
        output = 'Failed to execute ' \
                 "[#{final_cmd.shelljoin}]': #{e.class} #{e.message}"
        success = false
      end

      total_output.concat(output)
      clean_output = output.strip

      if success
        @logger.debug "Output: #{clean_output}"
      else
        @logger.error "Output: #{clean_output}"
        break
      end
    end

    {
      success: success,
      output:  total_output
    }
  end

  def self.do_or_die(cmd, logger)
    logger.info "Running '#{cmd}'"
    output, status = capture({}, cmd)
    logger.debug output
    unless status.exitstatus.zero?
      logger.error "#{cmd} exited with status #{status.exitstatus}"
      exit 1
    end
    output
  end

  # run Open3.capture2e with no shell
  def self.capture(env, cmd)
    raise InvalidTaskError, "Command can't be empty" if cmd.empty?

    prog, *args = cmd
    Open3.capture2e(env, [prog, prog], *args)
  end

  private

  def needs_rstar_arg(cmd)
    !@args['rstar_dir'].nil? &&
      cmd.none? { |arg| ['-r', '--rstar'].include?(arg) }
  end
end
