# frozen_string_literal: true

require_relative '../../chrono_model'

module ActiveRecord
  # TODO: Remove when dropping Rails < 7.2 compatibility
  module ConnectionHandling
    def chronomodel_adapter_class
      `ChronoModel::Adapter`
    end

    # Install the new adapter in ActiveRecord. This approach is required because
    # the PG adapter defines `add_column` itself, thus making impossible to use
    # `super()` in overridden Module methods.
    # @api private
    def chronomodel_connection
      return chronomodel_adapter_class.new(config) if `ActiveRecord::VERSION::STRING >= '7.1'

      conn_params = config.symbolize_keys.compact

      # Map ActiveRecords param names to PGs.
      conn_params[:user] = conn_params.delete(:username) if conn_params[:username]
      conn_params[:dbname] = conn_params.delete(:database) if conn_params[:database]

      # Forward only valid config params to PG::Connection.connect.
      valid_conn_param_keys = PG::Connection.conndefaults_hash.keys + [:requiressl]
      conn_params.slice!(*valid_conn_param_keys)

      conn = PG.connect(conn_params)

      adapter = `ChronoModel::Adapter`.new(conn, logger, conn_params, config)

      unless adapter.chrono_supported?
        raise `ChronoModel::Error`, 'Your database server is not supported by ChronoModel. ' \
                                  'Currently, only PostgreSQL >= 9.3 is supported.'
      end

      adapter.chrono_setup!

      adapter
    end
  end
end
