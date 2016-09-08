#!/usr/bin/env ruby

require 'mediainfo'
require_relative './cmd'

class Video

  def initialize(args)
    @args = args.clone
    @logger = @args['logger']
    @cmd = Cmd.new(@args)
  end

  def transcode
    if !@args['rstar_dir'].nil?
      transcode_wip
    else
      transcode_dir
    end
  end

  def transcode_dir
    cmds = get_transcode_cmds(@args['input_dir'], @args['output_dir'])
    @cmd.do_cmd(*cmds)
  end

  def transcode_wip
    cmds = Array.new
    @args['identifiers'].each do |id|
      @logger.debug "Processing #{id}"
      data_dir = "#{@args['rstar_dir']}/wip/se/#{id}/data"
      aux_dir  = "#{@args['rstar_dir']}/wip/se/#{id}/aux"
      @logger.debug "data dir: #{data_dir}"
      cmds.concat(get_transcode_cmds(data_dir, aux_dir))
    end
    @logger.debug cmds.inspect
    @cmd.do_cmd(*cmds)
  end

  def get_transcode_cmds(input_dir, output_dir)
    cmds = Array.new
    input_files = Dir.glob("#{input_dir}/*_d.{avi,mkv,mov,mp4}")
    input_files.each do |input_file|
      @logger.debug "Input_file: #{input_file}"
      basename = File.basename(input_file, ".*")
      basename.sub!(/_d$/, '')
      output_base = "#{output_dir}/#{basename}"
      cs_file = "#{output_base}_contact_sheet.jpg"
      @logger.debug "Output base: #{output_base}"
      cmds << "convert2mp4 -q "\
              "--path_tmpdir /content/prod/rstar/tmp "\
              "#{@args['extra_args']} "\
              "#{input_file} #{output_base}"
      if !File.file?(cs_file)
        cmds << "vcs -q -Wc -n 8 -o #{cs_file} #{input_file}"
      end
    end
    return cmds
  end

end

