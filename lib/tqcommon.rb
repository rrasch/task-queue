# frozen_string_literal: true

require 'resolv'
require 'socket'
require 'yaml'

# Provides common functionality for the task queue
module TQCommon
  INSTALL_DIR = '/usr/local/dlib/task-queue'

  module_function

  def env
    /^d/ =~ Socket.gethostname ? 'dev' : 'prod'
  end

  def rstar_dir
    "/content/#{env}/rstar"
  end

  def tmpdir
    "#{rstar_dir}/tmp"
  end

  def sysconfig
    conf_file = "/content/#{env}/rstar/etc/task-queue.sysconfig"
    config = {}
    File.foreach(conf_file) do |line|
      line.strip!
      next if line.empty? || line.start_with?('#')

      key, value = line.split('=', 2).map(&:strip)
      config[key.downcase] = value
    end
    config
  end

  def host_aliases
    alias_file = "/content/#{env}/rstar/etc/host-aliases.yaml"
    aliases = {}
    if File.exist?(alias_file)
      aliases = YAML.load_file(alias_file)['aliases']
      aliases = aliases.transform_keys { |name| name[/^[^.]+/] }
    end
    aliases
  end

  def services
    # services_file = "/content/#{env}/rstar/etc/services.yaml"
    services_file = File.expand_path('../services.yaml', File.dirname(__FILE__))
    YAML.load_file(services_file)['services']
  end

  def smtp_host
    config = sysconfig
    config.fetch('smtphost', 'localhost')
  end

  def hostname(host)
    if /\A(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\Z/ =~ host
      begin
        host = Resolv.getname(host)[/^[^.]+/]&.downcase || host
      rescue Resolv::ResolvError
        nil
      end
    end
    host
  end
end
