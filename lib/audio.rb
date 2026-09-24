# frozen_string_literal: true

require 'mediainfo'
require 'shellwords'
require_relative './cmd'
require_relative './exceptions'
require_relative './tqcommon'

# Class to execute audio jobs
class Audio
  LAYOUT = {
    1 => 'mono',
    2 => 'stereo',
    6 => '5.1',
    8 => '7.1'
  }.freeze

  ENVIRON = {
    'PYTHONPATH' => TQCommon::INSTALL_DIR,
    'TMPDIR'     => TQCommon.tmpdir
  }.freeze

  def initialize(args, logger)
    @args = args.dup
    @logger = logger
    @args['env'] = ENVIRON
    @cmd = Cmd.new(@args, @logger)
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
    @cmd.do_cmd(["#{TQCommon::INSTALL_DIR}/services/bin/transcribe.py",
                 *@args['extra_args'].shellsplit,
                 @args['input_path'],
                 @args['output_path']])
  end

  private

  def transcode_dir
    cmds = dir_transcode_cmds(@args['input_path'], @args['output_path'])
    @cmd.do_cmd(*cmds)
  end

  def transcode_wip
    cmds = @args['identifiers'].flat_map do |id|
      @logger.debug "Processing #{id}"
      data_dir = "#{@args['rstar_dir']}/wip/se/#{id}/data"
      aux_dir  = "#{@args['rstar_dir']}/wip/se/#{id}/aux"
      @logger.debug "data dir: #{data_dir}"
      dir_transcode_cmds(data_dir, aux_dir)
    end
    @logger.debug "wip cmds: #{cmds}"
    @cmd.do_cmd(*cmds)
  end

  def transcode_file
    @cmd.do_cmd(transcode_cmd(@args['input_path'], @args['output_path']))
  end

  def mezz_audio_files(input_path)
    audio_files = Dir.glob("#{input_path}/*_m.{mp3,wav}")
    unless audio_files.any?
      raise InvalidTaskError,
            "No mezzanine audio files found in #{input_path}"
    end
    audio_files
  end

  def dir_transcode_cmds(input_path, output_path)
    mezz_audio_files(input_path).map do |input_file|
      @logger.debug "Input_file: #{input_file}"
      basename = File.basename(input_file, '.*').sub(/_m$/, '')
      output_file = "#{output_path}/#{basename}_s.m4a"
      @logger.debug "Output file: #{output_file}"
      transcode_cmd(input_file, output_file)
    end
  end

  # rubocop:disable Metrics/MethodLength
  def transcode_cmd(input_file, output_file)
    minfo = get_media_info(input_file)
    [
      'ffmpeg',
      '-y',
      '-nostats',
      '-loglevel', 'warning',
      *channel_layout_args(minfo),
      '-i', input_file,
      '-c:a', 'libfdk_aac',
      '-b:a', "#{minfo.audio.channels * 64}k",
      '-ar', '48k',
      '-movflags', '+faststart',
      *@args['extra_args'].shellsplit,
      output_file
    ]
  end
  # rubocop:enable Metrics/MethodLength

  def get_media_info(input_file)
    info = MediaInfo.from(input_file)

    unless info.audio?
      raise InvalidTaskError, "Missing audio in media file #{input_file}"
    end

    info
  end

  def channel_layout_args(minfo)
    layout = LAYOUT[minfo.audio.channels]
    minfo.general.format == 'Wave' && layout ? ['-channel_layout', layout] : []
  end
end
