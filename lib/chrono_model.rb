# frozen_string_literal: true

require 'active_record'

require_relative 'chrono_model/chrono'
require_relative 'chrono_model/conversions'
require_relative 'chrono_model/patches'
require_relative 'chrono_model/adapter'
require_relative 'chrono_model/time_machine'
require_relative 'chrono_model/time_gate'
require_relative 'chrono_model/version'

require_relative 'chrono_model/railtie' if defined?(Rails::Railtie)
require_relative 'chrono_model/db_console' if defined?(Rails::DBConsole) && Rails.version < '7.1'

# ChronoModel provides temporal database functionality for PostgreSQL using Active Record.
#
# This gem implements Type-2 Slowly-Changing Dimensions through Oracle-style
# "Flashback Queries" using updatable views, table inheritance, and INSTEAD OF triggers.
module ChronoModel
  # Base error class for ChronoModel-specific errors.
  # @api private
  class Error < ActiveRecord::ActiveRecordError # :nodoc:
  end

  # Performs structure upgrade on the database connection.
  #
  # @raise [ChronoModel::Error] if the connection is not a ChronoModel::Adapter
  # @return [void]
  def self.upgrade!
    connection = ActiveRecord::Base.connection

    unless connection.is_a?(ChronoModel::Adapter)
      raise ChronoModel::Error, 'This database connection is not a ChronoModel::Adapter'
    end

    connection.chrono_upgrade!
  end

  # Returns an Hash keyed by table name of ChronoModels.
  # Computed upon inclusion of the +TimeMachine+ module.
  #
  # @return [Hash] hash of history models keyed by table name
  def self.history_models
    @history_models ||= {}
  end
end

ActiveSupport.on_load :active_record do
  extend ChronoModel::Chrono

  # Hooks into Association#scope to pass the As-Of time automatically
  # to methods that load associated ChronoModel records.
  ActiveRecord::Associations::Association.prepend ChronoModel::Patches::Association

  # Hooks into Relation#build_arel to use `:joins` on your ChronoModels
  # and join data from associated records As-Of time.
  ActiveRecord::Relation.prepend ChronoModel::Patches::Relation

  # Hooks in two points of the AR Preloader to preload As-Of time records of
  # associated ChronoModels. is used by `.includes`, `.preload`, and `.eager_load`.
  ActiveRecord::Associations::Preloader.prepend ChronoModel::Patches::Preloader

  ActiveRecord::Associations::Preloader::Association.prepend ChronoModel::Patches::Preloader::Association

  ActiveRecord::Associations::Preloader::ThroughAssociation.prepend ChronoModel::Patches::Preloader::ThroughAssociation

  ActiveRecord::Batches.prepend ChronoModel::Patches::Batches
end

ActiveSupport.on_load :after_initialize do
  next if Rails.application.config.active_record.schema_format == :sql

  raise 'In order to use ChronoModel, set `config.active_record.schema_format` to `:sql`'
end

if ActiveRecord::ConnectionAdapters.respond_to?(:register)
  ActiveRecord::ConnectionAdapters.register 'chronomodel', 'ChronoModel::Adapter', 'chrono_model/adapter'
end
