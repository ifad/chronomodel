require 'pathname'
require 'active_record'

module ChronoTest
  extend self

  AR = ActiveRecord::Base
  log = ENV['VERBOSE'].present? ? $stderr : 'spec/debug.log'.tap { |f| File.open(f, "ab") { |ft| ft.truncate(0) } }
  AR.logger = ::Logger.new(log).tap do |l|
    l.level = 0
  end

  def connect!(spec = config)
    unless ENV['VERBOSE'].present?
      spec = spec.merge(min_messages: 'WARNING')
    end
    AR.establish_connection spec
  end

  def logger
    AR.logger
  end

  def connection
    AR.connection
  end
  alias adapter connection

  def recreate_database!
    database = config.fetch(:database)
    connect! config.merge(database: :postgres)

    connection.drop_database   database
    connection.create_database database
    connect! config

    connection.execute 'CREATE EXTENSION btree_gist'
    logger.info "Connected to #{config}"
  end

  def config
    @config ||= YAML.load(config_file.read).tap do |conf|
      conf.symbolize_keys!
      conf.update(adapter: 'chronomodel')

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
