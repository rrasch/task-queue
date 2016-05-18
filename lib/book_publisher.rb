#!/usr/bin/env ruby

require 'fileutils'
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

  def exec_cmd(script_name)
    if @args.key?('rstar_dir')
      @cmd.do_cmd(script_name)
    else
      rstar_wrap(script_name)
    end
  end

  def rstar_wrap(script_name)
    mets_file = Dir.glob("#{@args['input_dir']}/*_mets.xml").first
    @logger.debug("METS file: #{mets_file}")
    id = File.basename(mets_file).sub(/_mets.xml$/, '')
    @logger.debug("wip id: #{id}")
    Dir.mktmpdir('task-queue') {|dir|
      rstar_dir = "#{dir}/wip/se/#{id}"
      data_dir  = "#{rstar_dir}/data"
      aux_dir   = "#{rstar_dir}/aux"
      FileUtils.mkdir_p(rstar_dir)
      FileUtils.ln_s(@args['input_dir'], data_dir)
      FileUtils.ln_s(@args['output_dir'], aux_dir)
      cmd = "#{BIN_DIR}/#{script_name} -q -r #{dir} #{id}"
      @logger.debug("Executing #{cmd}")
      @cmd.do_cmd(cmd)
    }
  end

end

