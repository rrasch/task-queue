# frozen_string_literal: true

require_relative './cmd'

# Class for utility services
class Util
  def initialize(args)
    @cmd = Cmd.new(args)
  end

  def ping
    @cmd.do_cmd('ping -c1 -W1 www.google.com')
  end

  def fortune
    @cmd.do_cmd('fortune')
  end

  def nope
    @cmd.do_cmd('false')
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def env
    ruby_info = <<~INFO
      Ruby Version: #{RUBY_VERSION}
      Patch Level: #{RUBY_PATCHLEVEL}
      Platform: #{RUBY_PLATFORM}
      Release Date: #{RUBY_RELEASE_DATE}
      Engine: #{defined?(RUBY_ENGINE) ? RUBY_ENGINE : 'ruby'}
      Description: #{RUBY_DESCRIPTION}
      Executable: #{RbConfig.ruby}
      Current Directory: #{Dir.pwd}
      Load Path: #{$LOAD_PATH.join(':')}
      Environment Variables Count: #{ENV.size}

      Gem environment:
      Gem Sources: #{Gem.default_sources.join(':')}
      Gem Directory: #{Gem.dir}
      Gem Path: #{Gem.path.join(':')}
    INFO

    ruby_bin_dir = File.dirname(RbConfig.ruby)
    ruby_bin_name = File.basename(RbConfig.ruby)
    gem_bin_path = File.join(ruby_bin_dir, ruby_bin_name.sub('ruby', 'gem'))
    gem_env_result = @cmd.do_cmd("#{gem_bin_path} env")

    installed_gems = Gem::Specification.sort_by(&:name).map do |spec|
      "#{spec.name} (#{spec.version})"
    end.join("\n")

    env_info = ENV.map { |key, value| "#{key}=#{value}" }.join("\n")

    full_info = <<~INFO
      #{ruby_info}
      # Output of '#{gem_bin_path} env':
      #{gem_env_result[:output]}
      Installed Gems:
      #{installed_gems}

      Environment Variables:
      #{env_info}
    INFO

    { success: false, output: full_info }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
