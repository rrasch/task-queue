#!/usr/bin/env ruby

require 'rubygems'
require 'sshkit'
require 'sshkit/dsl'
include SSHKit::DSL

if ENV.key?('DEPLOY_HOSTS')
  hosts = ENV['DEPLOY_HOSTS'].split(/\s/)
else
  hosts = %w{rasan@test}
end

mqhost = ENV['MQHOST'] || "localhost"

repo = 'https://github.com/rrasch/task-queue.git'

install_dir = '/usr/local/dlib/task-queue'

tmp_dir = '/var/lib/task-queue'

SSHKit.config.umask = '0007'

on hosts do |host|
  if test "[ -d #{install_dir} ]"
    within install_dir do
      execute :git, :stash
      execute :git, :pull
      execute :git, :stash, :clear
      execute :perl, '-pi', '-e', '\'s,^#!/usr/bin/env ruby,'\
              '#!/usr/local/dlib/task-queue/rubywrap,\'',
              '*.rb', 'lib/*.rb'
    end
  else
    execute :git, :clone, repo, install_dir
  end
  within tmp_dir do
    with mqhost: mqhost do
      execute :touch, 'updated'
    end
  end
end

