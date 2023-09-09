# frozen_string_literal: true

require 'pathname'
require 'active_record'

module ChronoTest
  AR = ActiveRecord::Base
  log = ENV['VERBOSE'].present? ? $stderr : 'spec/debug.log'.tap { |f| File.open(f, 'ab') { |ft| ft.truncate(0) } }
  AR.logger = ::Logger.new(log).tap do |l|
    l.level = 0
  end

  module_function

  def connect!(spec = config)
    spec = spec.merge(min_messages: 'WARNING') if ENV['VERBOSE'].blank?
    AR.establish_connection spec
  end

  def logger
    @logger ||= AR.logger
  end

  def connection
    AR.connection
  end

  def adapter
    @adapter ||= connection
  end

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
    @config ||= YAML.safe_load(config_file.read).tap do |conf|
      conf.symbolize_keys!
      conf.update(adapter: 'chronomodel')

      def conf.to_s
        format('pgsql://%<username>s:%<password>s@%<host>s/%<database>s', **slice(:username, :password, :host, :database))
      end
    end
  rescue Errno::ENOENT
    warn <<-MSG.squish
      Please define your AR database configuration
      in spec/config.yml or reference your own configuration
      file using the TEST_CONFIG environment variable
    MSG

    abort
  end

  def config_file
    Pathname(ENV['TEST_CONFIG'] || File.join(File.dirname(__FILE__), '..', 'config.yml'))
  end
end
