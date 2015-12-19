#!/usr/bin/env ruby

require './lib/cmd'

class Video

  def initialize(rstar_dir, ids, logger)
    @cmd = Cmd.new(rstar_dir, ids, logger)
  end

  def transcode
    @cmd.do_cmd('create-mp4')
  end

  def make_contact_sheet
    @cmd.do_cmd('vcs')
  end

end

