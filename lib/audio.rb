#!/usr/bin/env ruby

require 'mediainfo'
require_relative './cmd'

class Audio

  LAYOUT = { 2 => 'stereo', 6 => '5.1' }

  def initialize(args)
    @args = args.clone
    @logger = @args['logger']
    @cmd    = Cmd.new(@args)
  end

  def transcode
    if !@args['rstar_dir'].nil?
      transcode_wip
    else
      transcode_dir
    end
  end

  def transcode_dir
    cmds = get_transcode_cmds(@args['input_path'], @args['output_path'])
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

  def get_transcode_cmds(input_path, output_path)
    cmds = Array.new
    input_files = Dir.glob("#{input_path}/*_m.{mp3,wav}")
    input_files.each do |input_file|
      @logger.debug "Input_file: #{input_file}"
      minfo = Mediainfo.new input_file
      num_channels = minfo.audio.channels
      bitrate = "#{num_channels * 64}k"
      if minfo.format == "Wave" && LAYOUT[num_channels] then
        ch_layout_arg = "-channel_layout #{LAYOUT[num_channels]}"
      end
      basename = File.basename(input_file, ".*")
      basename.sub!(/_m$/, '')
      output_file = "#{output_path}/#{basename}_s.m4a"
      @logger.debug "Output file: #{output_file}"
      cmds << "ffmpeg -y -nostats -loglevel warning "\
              "#{ch_layout_arg} -i #{input_file} -c:a libfdk_aac "\
              "-b:a #{bitrate} -ac #{num_channels} "\
              "-ar 44.1k -movflags +faststart #{output_file}"
    end
    return cmds
  end

end

