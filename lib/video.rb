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
    elsif !@args['input_path'].nil?
      if File.directory?(@args['input_path'])
        transcode_dir
      else
        transcode_file
      end
    else
      @logger.error "Video.transcode: Must specify rstar_dir or input_path."
      { :status => false }
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
    @cmd.do_cmd("convert2mp4 -q "\
            "--path_tmpdir /content/prod/rstar/tmp "\
            "--video_threads 1 "\
            "#{@args['extra_args']} "\
            "#{@args['input_path']} #{@args['output_path']}")
  end

  def get_transcode_cmds(input_path, output_path)
    cmds = Array.new
    input_files = Dir.glob("#{input_path}/*_d.{avi,mkv,mov,mp4}")
    input_files.each do |input_file|
      @logger.debug "Input_file: #{input_file}"
      basename = File.basename(input_file, ".*")
      basename.sub!(/_d$/, '')
      output_base = "#{output_path}/#{basename}"
      cs_file = "#{output_base}_contact_sheet.jpg"
      @logger.debug "Output base: #{output_base}"
      cmds << "convert2mp4 -q "\
              "--path_tmpdir /content/prod/rstar/tmp "\
              "--video_threads 1 "\
              "#{@args['extra_args']} "\
              "#{input_file} #{output_base}"
      if !File.file?(cs_file)
        cmds << "vcs -q -Wc -n 8 -o #{cs_file} #{input_file}"
      end
    end
    return cmds
  end

end

