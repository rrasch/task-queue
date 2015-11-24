#!/usr/bin/env ruby

require cmd

class Video

  def initialize(rstar_dir, ids, logger)
    @cmd = Cmd.new(rstar_dir, ids, logger)
  end

  def transcode
    @cmd.exec('convert2mp4')
  end

  def make_contact_sheet
    @cmd.exec('vcs')
  end

end

