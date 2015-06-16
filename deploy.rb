#!/usr/bin/env ruby

require 'sshkit'
require 'sshkit/dsl'

hosts = %w{rasan@test}

mqhost = "localhost"

repo = 'https://github.com/rrasch/task-queue.git'

install_dir = '/usr/local/dlib/task-queue'

on hosts do |host|
  if test "[ -d #{install_dir} ]"
    within install_dir do
      execute :git, :pull
    end
  else
    execute :git, :clone, repo, install_dir
  end
  within install_dir do
    with mqhost: mqhost do
      #execute './workersctl', 'restart'
      puts capture('./workersctl', 'restart')
    end
  end
end

