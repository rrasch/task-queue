#!/usr/bin/env ruby

require 'fileutils'
require 'securerandom'
require 'tmpdir'
require_relative './cmd'

class BookPublisher

  BIN_DIR = "/usr/local/dlib/book-publisher/bin"

  def initialize(args)
    @args = args.clone
    @logger = args['logger']
    @args['bin_dir'] = BIN_DIR
    @cmd = Cmd.new(@args)
  end

  def create_derivatives
    exec_cmd('create-deriv-images.pl')
  end

  def stitch_pages
    exec_cmd('stitch-pages.pl')
  end

  def create_pdf
    exec_cmd('create-pdf.pl')
  end

  def create_ocr
    exec_cmd('create-ocr.pl')
  end

  def create_map
    exec_cmd('gen-kml.pl')
  end

  def gen_all
    exec_cmd('create-deriv-images.pl',
                'stitch-pages.pl',
                'create-pdf.pl')
  end

  def exec_cmd(*script_names)
    if !@args['rstar_dir'].nil?
      @cmd.do_cmd(*script_names)
    else
      rstar_wrap(*script_names)
    end
  end

  def rstar_wrap(*script_names)
    mets_file = Dir.glob("#{@args['input_path']}/*_mets.xml").first
    if mets_file.nil?
      @logger.warn "Can't find METS file. Generating random id ..."
      id = SecureRandom.uuid
    else
      @logger.debug("METS file: #{mets_file}")
      id = File.basename(mets_file).sub(/_mets.xml$/, '')
    end
    @logger.debug("wip id: #{id}")
    Dir.mktmpdir('task-queue') {|dir|
      rstar_dir = "#{dir}/wip/se/#{id}"
      data_dir  = "#{rstar_dir}/data"
      aux_dir   = "#{rstar_dir}/aux"
      FileUtils.mkdir_p(rstar_dir)
      FileUtils.ln_s(@args['input_path'], data_dir)
      FileUtils.ln_s(@args['output_path'], aux_dir)
      cmds = Array.new
      script_names.each do |script_name|
        rstar_cmd = "#{BIN_DIR}/#{script_name} -q -r #{dir} "\
                    "#{@args['extra_args']} #{id}"
        @logger.debug("rstar_wrap cmd: #{rstar_cmd}")
        cmds.push(rstar_cmd)
      end
      @cmd.do_cmd(*cmds)
    }
  end

end

