require 'pathname'
require 'active_record'
require 'active_support/core_ext/logger'

module ChronoTest
  extend self

  AR = ActiveRecord::Base
  AR.logger = ::Logger.new($stderr).tap do |l|
    l.level = 0
  end

  def connect!(spec = self.config)
    AR.establish_connection spec
  end

  def logger
    AR.logger
  end

  def connection
    AR.connection
  end

  def recreate_database!
    database = config.fetch(:database)
    connect! config.merge(:database => 'postgres')

    unless AR.supports_chrono?
      raise 'Your postgresql version is not supported. >= 9.0 is required.'
    end

    connection.drop_database   database
    connection.create_database database

  ensure
    connect!
    logger.info "Connected to #{config}"
  end

  def config
    @config ||= YAML.load(config_file.read).tap do |conf|
      conf.symbolize_keys!
      conf.update(:adapter => 'postgresql')

      def conf.to_s
        'pgsql://%s:%s@%s/%s' % [
          self[:username], self[:password], self[:hostname], self[:database]
        ]
      end
    end

  rescue Errno::ENOENT
    $stderr.puts <<EOM

Please define your AR database configuration
in spec/config.yml or reference your own configuration
file using the TEST_CONFIG environment variable
EOM

    abort
  end

  def config_file
    Pathname(ENV['TEST_CONFIG'] ||
      File.join(File.dirname(__FILE__), '..', 'config.yml')
    )
  end

end
