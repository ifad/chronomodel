require 'chrono_model'

module ActiveRecord
  class Base

    # Install the new adapter in ActiveRecord. This approach is required because
    # the PG adapter defines +add_column+ itself, thus making impossible to use
    # super() in overridden Module methods.
    #
    def self.chronomodel_connection(config) # :nodoc:
      config = config.symbolize_keys
      host     = config[:host]
      port     = config[:port] || 5432
      username = config[:username].to_s if config[:username]
      password = config[:password].to_s if config[:password]

      if config.key?(:database)
        database = config[:database]
      else
        raise ArgumentError, "No database specified. Missing argument: database."
      end

      # The postgres drivers don't allow the creation of an unconnected PGconn object,
      # so just pass a nil connection object for the time being.
      adapter = ChronoModel::Adapter.new(nil, logger, [host, port, nil, nil, database, username, password], config)

      unless adapter.chrono_supported?
        raise ChronoModel::Error, "Your database server is not supported by ChronoModel. "\
          "Currently, only PostgreSQL >= 9.3 is supported."
      end

      return adapter
    end

    ChronoModelAdapter = ::ChronoModel::Adapter

  end
end

