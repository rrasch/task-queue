#!/usr/bin/env ruby

require 'open3'

class BookPublisher

  BIN_DIR = "/usr/local/dlib/book-publisher/bin"

  attr_accessor :rstar_dir
  attr_accessor :ids
  attr_accessor :logger

  def create_derivatives?
    do_cmd('create-deriv-images.pl')
  end

  def stitch_pages?
    do_cmd('stitch-pages.pl')
  end

  def create_pdf?
    do_cmd('create-pdf.pl')
  end

  def gen_all?
    do_cmd('create-deriv-images.pl') &&
    do_cmd('stitch-pages.pl') &&
    do_cmd('create-pdf.pl')
  end

  def do_cmd?(script_name)
    cmd = BIN_DIR + "/#{script_name} -q -r #{rstar_dir} #{ids.join(',')}"
    output, status = Open3.capture2e(cmd)
    logger.debug output
    return !status.exitstatus
  end

end

