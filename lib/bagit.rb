# frozen_string_literal: true

require 'open3'
require 'shellwords'
require_relative './cmd'
require_relative './exceptions'

# Class for validating bagit directories
class Bagit
  BIN_DIR = '/content/prod/rstar/bin'

  BAGIT_CMD = "#{BIN_DIR}/bagit/bag"

  def initialize(args, logger)
    @args = args.dup
    @logger = logger
    @cmd = Cmd.new(@args, @logger)
  end

  def validate # rubocop:disable Metrics/MethodLength
    unless @args['input_path']
      raise InvalidTaskError, 'Bagit.validate: Must specify input_path.'
    end

    Dir.mktmpdir('bagit-') do |tmp_dir|
      props_file = File.join(tmp_dir, 'log4j.properties')
      write_log4j_properties(props_file, @args['output_path'])
      @cmd['env'] =
        { 'JAVA_OPTS' => "-Dlog4j.configuration=file:#{props_file}" }
      @cmd.do_cmd([BAGIT_CMD,
                   'verifyvalid',
                   @args['input_path'],
                   '--log-verbose',
                   *@args['extra_args'].shellsplit])
    end
  end

  private

  def write_log4j_properties(properties_file, log_file)
    File.write(properties_file, <<~PROPERTIES)
      # Set root logger level to DEBUG and its appenders to CONSOLE and R.
      log4j.rootLogger=ALL, R

      # File
      log4j.appender.R=org.apache.log4j.FileAppender
      log4j.appender.R.File=#{log_file}
      log4j.appender.R.layout=org.apache.log4j.PatternLayout
      log4j.appender.R.layout.ConversionPattern=%d [%t] %-5p %C{1} : %m%n

      # LIMIT CATEGORIES
      log4j.logger.gov.loc.repository=INFO
      log4j.logger.org.apache.http=INFO
    PROPERTIES
  end
end
