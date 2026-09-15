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
    if !@args['rstar_dir'].nil?
      transcode_wip
    elsif !@args['input_path'].nil?
      if File.directory?(@args['input_path'])
        transcode_dir
      else
        transcode_file
      end
    else
      raise InvalidTaskError,
            'Video.transcode: Must specify rstar_dir or input_path.'
    end
  end

  def convert_iso
    logdir = File.join(ENVIRON['TMPDIR'], 'rstar', 'logs')
    timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
    pid = Process.pid
    basename = File.basename(
      @args['output_path'],
      File.extname(@args['output_path'])
    )
    logfile = File.join(logdir, "#{basename}-#{timestamp}-#{pid}.log")
    @cmd.do_cmd(['convert_iso',
                 '--quiet',
                 '--threads', '1',
                 '--log-file', logfile,
                 @args['extra_args'],
                 @args['input_path'],
                 @args['output_path']])
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

  def build_conv_cmd(input_path, output_path)
    ['convert2mp4',
     '--quiet',
     '--path_tmpdir', ENVIRON['TMPDIR'],
     '--video_threads', '1',
     *@args['extra_args'].shellsplit,
     input_path,
     output_path]
  end

  def transcode_file
    build_conv_cmd(@args['input_path'], @args['output_path'])
  end

  def get_transcode_cmds(input_path, output_path)
    cmds = []
    input_files = Dir.glob("#{input_path}/*_d.{avi,mkv,mov,mp4}")
    input_files.each do |input_file|
      @logger.debug "Input_file: #{input_file}"
      basename = File.basename(input_file, '.*')
      basename.sub!(/_d$/, '')
      output_base = "#{output_path}/#{basename}"
      cs_file = "#{output_base}_contact_sheet.jpg"
      @logger.debug "Output base: #{output_base}"
      cmds << build_conv_cmd(input_file, output_base)
      unless File.file?(cs_file)
        cmds << ['vcs', '-q', '-Wc', '-n', '8', '-o', cs_file, input_file]
      end
    end
    cmds
  end
end
