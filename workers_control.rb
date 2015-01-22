#!/usr/bin/env ruby

require 'daemons'

options = {
  :app_name   => "workers",
  :dir_mode   => :script,
  :dir        => 'pids',
  :multiple   => false,
  :ontop      => false,
#   :mode       => :exec,
#   :backtrace  => true,
  :monitor    => true,
  :log_dir    => "logs"
}

# Daemons.run('myserver.rb')
Daemons.run('/home/rasan/work/bag-validator/workers.rb', options)

