require 'resolv'
require 'socket'
require 'yaml'

module TQCommon

  def self.get_env
    env = /^d/ =~ Socket.gethostname ? "dev" : "prod"
    return env
  end

  def self.get_sysconfig
    conf_file = "/content/#{get_env()}/rstar/etc/task-queue.sysconfig"
    config = {}
    File.foreach(conf_file) do |line|
      line.strip!
      next if line.empty? || line.start_with?("#")
      key, value = line.split("=", 2).map(&:strip)
      config[key.downcase] = value
    end
    return config
  end

  def self.get_host_aliases
    alias_file = "/content/#{get_env()}/rstar/etc/host-aliases.yaml"
    aliases = {}
    if File.exist?(alias_file)
      aliases = YAML.load_file(alias_file)["aliases"]
      aliases = aliases.map { |name, nick| [name[/^[^.]+/], nick] }.to_h
    end
    return aliases
  end

  def self.get_smtp_host
    config = get_sysconfig()
    return config.fetch("smtphost", "localhost")
  end

  def self.get_hostname(host)
    if /\A(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\Z/ =~ host
      begin
        host = Resolv.getname(host)[/^[^.]+/].downcase
      rescue Resolv::ResolvError => e
        # Do nothing
      end
    end
    return host
  end

end
