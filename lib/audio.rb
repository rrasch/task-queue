#!/usr/bin/env ruby

require 'mediainfo'
require './lib/cmd'

class Audio

  LAYOUT = { 2 => 'stereo', 6 => '5.1' }

  def initialize(rstar_dir, ids, logger)
    @rstar_dir = rstar_dir
    @ids = ids
    @logger = logger
    @cmd = Cmd.get_cmd(logger)
  end

  def transcode
    cmds = Array.new
    @ids.each do |id|
      @logger.debug "Processing #{id}"
      data_dir = "#{@rstar_dir}/wip/se/#{id}/data"
      aux_dir  = "#{@rstar_dir}/wip/se/#{id}/aux"
      @logger.debug "data dir: #{data_dir}"
      input_files = Dir.glob("#{data_dir}/*_m.{mp3,wav}")
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
        output_file = "#{aux_dir}/#{basename}_s.m4a"
        @logger.debug "Output file: #{output_file}"
        cmds << "ffmpeg -y -nostats -loglevel warning "\
                "#{ch_layout_arg} -i #{input_file} -c:a libfdk_aac "\
                "-b:a #{bitrate} -ac #{num_channels} "\
                "-ar 44.1k -movflags +faststart #{output_file}"
      end
    end
    @cmd.do_cmd(*cmds)
  end

end

