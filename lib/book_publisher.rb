#!/usr/bin/env ruby

require_relative './cmd'

class BookPublisher

  BIN_DIR = "/usr/local/dlib/book-publisher/bin"

  def initialize(args)
    @args = args.clone
    @args['bin_dir'] = BIN_DIR
    @cmd = Cmd.new(@args)
  end

  def create_derivatives
    @cmd.do_cmd('create-deriv-images.pl')
  end

  def stitch_pages
    @cmd.do_cmd('stitch-pages.pl')
  end

  def create_pdf
    @cmd.do_cmd('create-pdf.pl')
  end

  def create_ocr
    @cmd.do_cmd('create-ocr.pl')
  end

  def create_map
    @cmd.do_cmd('gen-kml.pl')
  end

  def gen_all
    @cmd.do_cmd('create-deriv-images.pl',
                'stitch-pages.pl',
                'create-pdf.pl')
  end

end

