require 'active_record'

require 'chrono_model/conversions'
require 'chrono_model/patches'
require 'chrono_model/adapter'
require 'chrono_model/time_machine'
require 'chrono_model/time_gate'
require 'chrono_model/version'

module ChronoModel
  class Error < ActiveRecord::ActiveRecordError #:nodoc:
  end

  # Performs structure upgrade.
  #
  def self.upgrade!
    connection = ActiveRecord::Base.connection

    unless connection.is_a?(ChronoModel::Adapter)
      raise ChronoModel::Error, "This database connection is not a ChronoModel::Adapter"
    end

    connection.send :chrono_upgrade!
  end

  # Returns an Hash keyed by table name of ChronoModels.
  # Computed upon inclusion of the +TimeMachine+ module.
  #
  def self.history_models
    @_history_models||= {}
  end
end

if defined?(Rails)
  require 'chrono_model/railtie'
end

ActiveRecord::Base.instance_eval do
  # Checks whether this Active Recoed model is backed by a temporal table
  #
  def chrono?
    connection.is_chrono?(table_name)
  end
end

# Hooks into Association#scope to pass the As-Of time automatically
# to methods that load associated ChronoModel records.
#
ActiveRecord::Associations::Association.instance_eval do
  prepend ChronoModel::Patches::Association
end

# Hooks into Relation#build_arel to use :joins on your ChronoModels
# and join data from associated records As-Of time.
#
ActiveRecord::Relation.instance_eval do
  prepend ChronoModel::Patches::Relation
end

# Hooks in two points of the AR Preloader to preload As-Of time records of
# associated ChronoModels. is used by .includes, .preload and .eager_load.
#
ActiveRecord::Associations::Preloader.instance_eval do
  prepend ChronoModel::Patches::Preloader
end

ActiveRecord::Associations::Preloader::Association.instance_eval do
  prepend ChronoModel::Patches::Preloader::Association
end

if defined?(Rails::DBConsole)
  Rails::DBConsole.instance_eval do
    prepend ChronoModel::Patches::DBConsole
  end
end
