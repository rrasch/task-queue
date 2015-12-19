#!/usr/bin/env ruby

require 'open3'

class BookPublisher

  BIN_DIR = "/usr/local/dlib/book-publisher/bin"

  def initialize(rstar_dir, ids, logger)
    @rstar_dir = rstar_dir
    @ids = ids
    @logger = logger
  end

  def create_derivatives
    do_cmd('create-deriv-images.pl')
  end

  def stitch_pages
    do_cmd('stitch-pages.pl')
  end

  def create_pdf
    do_cmd('create-pdf.pl')
  end

# def gen_all
#   do_cmd('create-deriv-images.pl') &&
#   do_cmd('stitch-pages.pl') &&
#   do_cmd('create-pdf.pl')
# end

  def gen_all
    do_cmd('create-deriv-images.pl', 'stitch-pages.pl', 'create-pdf.pl')
  end

  def do_cmd(*script_names)
    total_output = ""
    success = true
    script_names.each do |script_name|
      cmd = BIN_DIR + "/#{script_name} -q -r #{@rstar_dir} #{@ids.join(' ')}"
      output, status = Open3.capture2e(cmd)
      @logger.debug output
      total_output.concat(output)
      success = status.exitstatus.zero?
      break if !success
    end
    return {
      :success => success,
      :output  => total_output,
    }
  end

end

