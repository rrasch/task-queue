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

  def validate
    unless @args['input_path']
      raise InvalidTaskError, 'Bagit.validate: Must specify input_path.'
    end

    @cmd.do_cmd([BAGIT_CMD,
                 'verifyvalid',
                 @args['input_path'],
                 '--noresultfile',
                 *@args['extra_args'].shellsplit])
  end
end
