#!/usr/bin/env ruby

require 'mediainfo'
require_relative './cmd'

class Video

  def initialize(args)
    @args = args.clone
    @logger = @args['logger']
    @args['add_rstar'] = true
    @cmd = Cmd.new(@args)
  end

  def transcode_wip
    @cmd.do_cmd('create-mp4')
  end

  def transcode_dir
    cmds = Array.new
    input_dir = @args['input_dir']
    output_dir = @args['output_dir']
    input_files = Dir.glob("#{input_dir}/*_m.{mov}")
    input_files.each do |input_file|
      @logger.debug "Input file: #{input_file}"
      basename = File.basename(input_file, ".*")
      basename.sub!(/_m$/, '')
      output_base = "#{output_dir}/#{basename}"
      cs_file = "#{output_base}_contact_sheet.jpg"
      @logger.debug "Output base: #{output_base}"
      cmds << "convert2mp4 -q #{@args['extra_args']} "\
              "#{input_file} #{output_base}"
      cmds << "vcs -q -Wc -o #{cs_file} #{input_file}"
    end
    @logger.debug("Will exectute #{cmds}")
    @cmd.do_cmd(*cmds)
  end

end

