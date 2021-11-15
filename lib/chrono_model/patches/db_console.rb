# frozen_string_literal: true

module ChronoModel
  module Patches
    module DBConsole
      module Config
        def config
          super.dup.tap { |config| config['adapter'] = 'postgresql/chronomodel' }
        end
      end

      module DbConfig
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
