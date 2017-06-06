require 'chrono_model'

module ActiveRecord
  module ConnectionHandling

    # Install the new adapter in ActiveRecord. This approach is required because
    # the PG adapter defines +add_column+ itself, thus making impossible to use
    # super() in overridden Module methods.
    #
    def chronomodel_connection(config) # :nodoc:
      conn_params = config.symbolize_keys

      conn_params.delete_if { |_, v| v.nil? }

      # Map ActiveRecords param names to PGs.
      conn_params[:user] = conn_params.delete(:username) if conn_params[:username]
      conn_params[:dbname] = conn_params.delete(:database) if conn_params[:database]

      # Forward only valid config params to PGconn.connect.
      valid_conn_param_keys = if ActiveRecord::VERSION::MAJOR == 4
                                VALID_CONN_PARAMS
                              else
                                PGconn.conndefaults_hash.keys + [:requiressl]
                              end
      conn_params.slice!(*valid_conn_param_keys)

      # The postgres drivers don't allow the creation of an unconnected PGconn object,
      # so just pass a nil connection object for the time being.
      adapter = ChronoModel::Adapter.new(nil, logger, conn_params, config)

      unless adapter.chrono_supported?
        raise ChronoModel::Error, "Your database server is not supported by ChronoModel. "\
          "Currently, only PostgreSQL >= 9.3 is supported."
      end

      adapter.chrono_setup!

      return adapter
    end

    module Connectionadapters
      ChronoModelAdapter = ::ChronoModel::Adapter
    end

  end
end

