# frozen_string_literal: true

require 'mediainfo'
require_relative './cmd'
require_relative './exceptions'
require_relative './tqcommon'

# Class to execute audio jobs
class Audio
  LAYOUT = { 1 => 'mono', 2 => 'stereo', 6 => '5.1' }.freeze

  ENVIRON = {
    'PYTHONPATH' => TQCommon::INSTALL_DIR,
    'TMPDIR' => TQCommon.tmpdir
  }.freeze

  def initialize(args)
    @args = args.clone
    @logger = @args['logger']
    @args['env'] = ENVIRON
    @cmd = Cmd.new(@args)
    @minfo_bin_version = `mediainfo --Version`[/v([\d.]+)/, 1]
    @minfo_gem_version = Gem.loaded_specs['mediainfo'].version
    verify_mediainfo_version
  end

  def transcode
    if @args['rstar_dir'].nil? && @args['input_path'].nil?
      raise InvalidTaskError,
            'Audio.transcode: Must specify rstar_dir or input_path.'
    end

    return transcode_wip unless @args['rstar_dir'].nil?

    return transcode_dir if File.directory?(@args['input_path'])

    transcode_file
  end

  def transcribe
    @cmd.do_cmd("#{TQCommon::INSTALL_DIR}/services/bin/transcribe.py " \
                "#{@args['extra_args']} " \
                "#{@args['input_path']} #{@args['output_path']}")
  end

  private

  def transcode_dir
    cmds = get_transcode_cmds(@args['input_path'], @args['output_path'])
    @cmd.do_cmd(*cmds)
  end

  def transcode_wip
    cmds = []
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
    cmds = []
    input_files = Dir.glob("#{input_path}/*_m.{mp3,wav}")
    input_files.each do |input_file|
      @logger.debug "Input_file: #{input_file}"
      basename = File.basename(input_file, '.*').sub!(/_m$/, '')
      output_file = "#{output_path}/#{basename}_s.m4a"
      @logger.debug "Output file: #{output_file}"
      cmds << transcode_cmd(input_file, output_file)
    end
    cmds
  end

  def transcode_cmd(input_file, output_file)
    minfo = get_media_info(input_file)
    num_channels = minfo.audio.channels
    bitrate = "#{num_channels * 64}k"
    ch_layout_arg = ''
    if minfo.general.format == 'Wave' && LAYOUT[num_channels]
      ch_layout_arg = "-channel_layout #{LAYOUT[num_channels]}"
    end
    build_ffmpeg_cmd(input_file, output_file, ch_layout_arg, num_channels,
                     bitrate)
  end

  def incompatible_mediainfo_versions?
    Gem::Version.new(@minfo_bin_version) <= Gem::Version.new('0.7.99') &&
      Gem::Version.new(@minfo_gem_version) >= Gem::Version.new('1.0.0')
  end

  def get_media_info(input_file)
    if Gem::Version.new(@minfo_gem_version) >= Gem::Version.new('1.0.0')
      MediaInfo.from(input_file)
    else
      Mediainfo.new(input_file)
    end
  end

  def verify_mediainfo_version
    if incompatible_mediainfo_versions? # rubocop:disable Style/GuardClause
      raise "Version of MediaInfo tool, #{@minfo_bin_version}, not " \
            "compatible with version #{@minfo_gem_version} of mediainfo gem."
    end
  end

  def build_ffmpeg_cmd(input_file, output_file, ch_layout_arg, num_channels,
                       bitrate)
    'ffmpeg -y -nostats -loglevel warning ' \
      "#{ch_layout_arg} -i '#{input_file}' -c:a libfdk_aac " \
      "-b:a #{bitrate} -ac #{num_channels} " \
      "-ar 44.1k -movflags +faststart '#{output_file}'"
  end
end
