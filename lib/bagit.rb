# frozen_string_literal: true

require 'open3'
require_relative './cmd'

# Class for validating bagit directories
class Bagit
  BIN_DIR = '/content/prod/rstar/bin'

  BAGIT_CMD = "#{BIN_DIR}/bagit/bag"

  def initialize(args)
    @args = args.clone
    @logger = @args['logger']
    @cmd = Cmd.new(args)
  end

  def validate
    unless @args['input_path']
      err_msg = 'Bagit.validate: Must specify input_path.'
      @logger.error(err_msg)
      return { success: false, output: err_msg }
    end
    @cmd.do_cmd("#{BAGIT_CMD} verifyvalid #{@args['input_path']}")
  end
end
