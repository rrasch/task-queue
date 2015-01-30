#!/usr/bin/env ruby

require 'open3'

class BookPublisher

  BIN_DIR = "/usr/local/dlib/book-publisher/bin"

  attr_accessor :rstar_dir
  attr_accessor :ids

  def create_derivatives
    cmd = mkcmd('create_deriv_images.pl')
    output, status = Open3.capture2e(cmd)
  end

  def stitch_pages
    cmd = mkcmd('stitch-pages.pl')
    output, status = Open3.capture2e(cmd)
  end

  def create_pdf
    cmd = mkcmd('create-pdf.pl')
    puts cmd
    output, status = Open3.capture2e(cmd)
    puts output
    status.exitstatus
  end

  def mkcmd(script_name)
    BIN_DIR + "/#{script_name} -r #{rstar_dir} #{ids.join(',')}"
  end

end

bp = BookPublisher.new
bp.rstar_dir = "/content/prod/rstar/content/nyu/aco"
bp.ids = ["nyu_aco000003"]
bp.create_pdf


