require 'mediainfo'
require_relative './cmd'

class Audio

  LAYOUT = { 1 => 'mono', 2 => 'stereo', 6 => '5.1' }

  def initialize(args)
    @args = args.clone
    @logger = @args['logger']
    @cmd = Cmd.new(@args)
    @minfo_bin_version = `mediainfo --Version`[/v([\d.]+)/, 1]
    @minfo_gem_version = Gem.loaded_specs['mediainfo'].version
  end

  def transcode
    # XXX: put this version check in initialize and throw exception
    if  Gem::Version.new(@minfo_bin_version) <=
        Gem::Version.new('0.7.99') &&
        Gem::Version.new(@minfo_gem_version) >=
        Gem::Version.new('1.0.0')
      @logger.error "Version of MediaInfo tool, "\
                    "#{@minfo_bin_version}, not compatible with version "\
                    "#{@minfo_gem_version} of mediainfo gem."
      return { :success => false }
    end
    if !@args['rstar_dir'].nil?
      transcode_wip
    elsif !@args['input_path'].nil?
      if File.directory?(@args['input_path'])
        transcode_dir
      else
        transcode_file
      end
    else
      @logger.error "Audio.transcode: Must specify rstar_dir or input_path."
      return { :success => false }
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

  def transcode_file
    @cmd.do_cmd(transcode_cmd(@args['input_path'], @args['output_path']))
  end

  def get_transcode_cmds(input_path, output_path)
    cmds = Array.new
    input_files = Dir.glob("#{input_path}/*_m.{mp3,wav}")
    input_files.each do |input_file|
      @logger.debug "Input_file: #{input_file}"
      basename = File.basename(input_file, ".*")
      basename.sub!(/_m$/, '')
      output_file = "#{output_path}/#{basename}_s.m4a"
      @logger.debug "Output file: #{output_file}"
      cmds << transcode_cmd(input_file, output_file)
    end
    return cmds
  end

  def transcode_cmd(input_file, output_file)
    ENV['MEDIAINFO_PATH'] = '/usr/bin/mediainfo'
    if Gem::Version.new(@minfo_gem_version) >= Gem::Version.new('1.0.0')
      minfo = MediaInfo.from(input_file)
    else
      minfo = Mediainfo.new input_file
    end
    num_channels = minfo.audio.channels
    bitrate = "#{num_channels * 64}k"
    if minfo.general.format == "Wave" && LAYOUT[num_channels] then
      ch_layout_arg = "-channel_layout #{LAYOUT[num_channels]}"
    end
    return "ffmpeg -y -nostats -loglevel warning "\
           "#{ch_layout_arg} -i '#{input_file}' -c:a libfdk_aac "\
           "-b:a #{bitrate} -ac #{num_channels} "\
           "-ar 44.1k -movflags +faststart '#{output_file}'"
  rescue Exception => ex
    @logger.error "#{ex.class} => #{ex.message}"
    return "false '#{input_file}' '#{output_file}'"
  end

end

