# frozen_string_literal: true

require 'mediainfo'
require 'shellwords'
require_relative './cmd'
require_relative './exceptions'
require_relative './tqcommon'

# Video is class for transcoding video files into mp4 files.
class Video
  ENVIRON = {
    'TMPDIR' => TQCommon.tmpdir
  }.freeze

  def initialize(args)
    @args = args.clone
    @logger = @args['logger']
    @args['env'] = ENVIRON
    @cmd = Cmd.new(@args)
  end

  def transcode
    if @args['rstar_dir'].nil? && @args['input_path'].nil?
      raise InvalidTaskError,
            'Video.transcode: Must specify rstar_dir or input_path.'
    end

    return transcode_wip unless @args['rstar_dir'].nil?

    return transcode_dir if File.directory?(@args['input_path'])

    transcode_file
  end

  def convert_iso
    @cmd.do_cmd(['convert_iso',
                 '--quiet',
                 '--threads', '1',
                 '--log-file', logfile,
                 *@args['extra_args'].shellsplit,
                 @args['input_path'],
                 @args['output_path']])
  end

  private

  def logfile
    logdir = File.join(ENVIRON['TMPDIR'], 'rstar', 'logs')
    timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
    basename = File.basename(
      @args['output_path'],
      File.extname(@args['output_path'])
    )
    File.join(logdir, "#{basename}-#{timestamp}-#{Process.pid}.log")
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

  def transcode_dir
    cmds = get_transcode_cmds(@args['input_path'], @args['output_path'])
    @cmd.do_cmd(*cmds)
  end

  def transcode_file
    @cmd.do_cmd(build_conv_cmd(@args['input_path'], @args['output_path']))
  end

  def get_transcode_cmds(input_path, output_path)
    cmds = []

    Dir.glob("#{input_path}/*_d.{avi,mkv,mov,mp4}").each do |input_file|
      @logger.debug "Input_file: #{input_file}"
      output_base = get_output_base(input_file, output_path)

      cs_file = "#{output_base}_contact_sheet.jpg"
      @logger.debug "Output base: #{output_base}"

      cmds << build_conv_cmd(input_file, output_base)
      cmds << build_vcs_cmd(input_file, cs_file) unless File.file?(cs_file)
    end

    cmds
  end

  def get_output_base(input_file, output_path)
    basename = File.basename(input_file, '.*')
    basename.sub!(/_d$/, '')
    File.join(output_path, basename)
  end

  def build_conv_cmd(input_path, output_path)
    [
      'convert2mp4',
      '--quiet',
      '--path_tmpdir', ENVIRON['TMPDIR'],
      '--video_threads', '1',
      *@args['extra_args'].shellsplit,
      input_path,
      output_path
    ]
  end

  def build_vcs_cmd(input_file, output_file)
    [
      'vcs',
      '--quiet',
      '-Wc',
      '--numcaps', '8',
      '--output', output_file,
      input_file
    ]
  end
end
