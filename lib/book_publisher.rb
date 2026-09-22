# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'shellwords'
require 'tmpdir'
require_relative './cmd'

# BookPublisher is class to perform book and image
# processing such as generating derivatives and pdfs.
class BookPublisher
  BIN_DIR = '/usr/local/dlib/book-publisher/bin'

  ENVIRON = {
    'MAGICK_THREAD_LIMIT' => '1',
    'OMP_THREAD_LIMIT'    => '1',
    'PYTHONPATH'          => '/usr/local/dlib/aco-scripts',
    'PERL5LIB'            => '/usr/local/dlib/book-publisher/lib'
  }.freeze

  def initialize(args)
    @args = args.clone
    @logger = args['logger']
    @args['bin_dir'] = BIN_DIR
    @args['env'] = ENVIRON
    @cmd = Cmd.new(@args)
  end

  def create_derivatives
    exec_cmd(['create-deriv-images.pl'])
  end

  def create_dmakers
    exec_cmd(['create-deriv-images.pl', '-m'])
  end

  def stitch_pages
    exec_cmd(['stitch-pages.pl'])
  end

  def create_pdf
    exec_cmd(['create-pdf.pl'])
  end

  def create_ocr
    exec_cmd(['create-ocr.pl'])
  end

  def create_map
    exec_cmd(['gen-kml.pl'])
  end

  def gen_all
    exec_cmd(['create-deriv-images.pl'],
             ['create-pdf.pl'])
  end

  # create low resolution pdf that will be uploaded
  # to yaiglobal to extract hocr
  def make_yaiglobal_upload_pdf
    opts = ['--force', '--lores']
    exec_cmd(['create-deriv-images.pl', *opts],
             ['create-pdf.pl', *opts],
             ['clean-aux.py', '--exclude', '_lo.pdf'])
  end

  def hocr2pdf
    exec_cmd(['create-deriv-images.pl', '--dmakers'],
             ['hocr2pdf.py'])
  end

  def shrink_aco_pdf
    @cmd.do_cmd(["#{BIN_DIR}/shrink-aco-pdf.py",
                 *@args['extra_args'].shellsplit,
                 @args['input_path'],
                 @args['output_path']])
  end

  private

  def exec_cmd(*cmd_list)
    if @args['rstar_dir'].nil?
      rstar_wrap(*cmd_list)
    else
      @cmd.do_cmd(*cmd_list)
    end
  end

  def book_id
    mets_file = Dir.glob("#{@args['input_path']}/*_mets.xml").first
    if mets_file.nil?
      @logger.warn "Can't find METS file. Generating random id ..."
      SecureRandom.uuid
    else
      @logger.debug("METS file: #{mets_file}")
      File.basename(mets_file).sub(/_mets.xml$/, '')
    end
  end

  def make_book_tree(tmp_dir, id)
    book_dir = "#{tmp_dir}/wip/se/#{id}"
    data_dir = "#{book_dir}/data"
    aux_dir  = "#{book_dir}/aux"
    FileUtils.mkdir_p(book_dir)
    FileUtils.ln_s(@args['input_path'], data_dir)
    FileUtils.ln_s(@args['output_path'], aux_dir)
  end

  def build_full_cmd(cmd, tmp_dir, id)
    prog, *args = cmd
    [
      "#{BIN_DIR}/#{prog}",
      *args,
      '-q',
      '-r', tmp_dir,
      *@args['extra_args'].shellsplit,
      id
    ]
  end

  def rstar_wrap(*cmd_list)
    id = book_id
    @logger.debug("id: #{id}")
    Dir.mktmpdir('task-queue') do |tmp_dir|
      make_book_tree(tmp_dir, id)
      full_cmd_list = cmd_list.map { |cmd| build_full_cmd(cmd, tmp_dir, id) }
      @logger.debug "Full command list: #{full_cmd_list}"
      @cmd.do_cmd(*full_cmd_list)
    end
  end
end
