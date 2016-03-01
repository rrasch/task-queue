#!/usr/bin/env ruby

require_relative './cmd'

class Video

  def initialize(args)
    @args = args.clone
    @args['add_rstar'] = true
    @cmd = Cmd.new(@args)
  end

  def transcode
    @cmd.do_cmd('create-mp4')
  end

end

