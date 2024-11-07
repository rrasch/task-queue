require 'socket'

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

  def self.get_smtp_host()
    config = get_sysconfig()
    return config.fetch("smtphost", "localhost")
  end

end
