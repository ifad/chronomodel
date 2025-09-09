# frozen_string_literal: true

module ChronoModel
  module Patches
    # Patches for Rails database console integration to support ChronoModel adapter.
    module DBConsole
      # Patches the Config module to modify adapter name for database console.
      module Config
        # Returns the database configuration with the adapter name modified for console compatibility.
        #
        # @return [Hash] database configuration with 'postgresql/chronomodel' adapter name
        def config
          super.dup.tap { |config| config['adapter'] = 'postgresql/chronomodel' }
        end
      end

      # Patches the DbConfig module to modify database configuration for console compatibility.
      module DbConfig
        # Returns the database configuration object with modified adapter name.
        #
        # The configuration is patched to use 'postgresql/chronomodel' as the adapter
        # name, ensuring proper database console functionality.
        #
        # @return [ActiveRecord::DatabaseConfigurations::DatabaseConfig] patched database configuration
        def db_config
          return @patched_db_config if @patched_db_config

          original_db_config = super
          patched_db_configuration_hash = original_db_config.configuration_hash.dup.tap do |config|
            config[:adapter] = 'postgresql/chronomodel'
          end
          original_db_config.instance_variable_set :@configuration_hash, patched_db_configuration_hash

          @patched_db_config = original_db_config
        end
      end
    end
  end
end
