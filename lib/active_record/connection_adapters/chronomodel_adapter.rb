# frozen_string_literal: true

require 'chrono_model'

module ActiveRecord
  module ConnectionHandling
    def chronomodel_adapter_class
      ConnectionAdapters::PostgreSQLAdapter
    end

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

      # Forward only valid config params to PG::Connection.connect.
      valid_conn_param_keys = PG::Connection.conndefaults_hash.keys + [:requiressl]
      conn_params.slice!(*valid_conn_param_keys)

      conn = PG.connect(conn_params) if ActiveRecord::VERSION::MAJOR >= 6

      adapter = ChronoModel::Adapter.new(conn, logger, conn_params, config)

      # Rails 7.2.0, see ifad/chronomodel#236
      adapter.connect! if adapter.respond_to?(:connect!)

      unless adapter.chrono_supported?
        raise ChronoModel::Error, 'Your database server is not supported by ChronoModel. ' \
                                  'Currently, only PostgreSQL >= 9.3 is supported.'
      end

      adapter.chrono_setup!

      adapter
    rescue ::PG::Error => e
      if e.message.include?(conn_params[:dbname])
        raise ActiveRecord::NoDatabaseError
      else
        raise
      end
    end
  end
end
