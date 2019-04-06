require 'chrono_model/version'
require 'chrono_model/adapter'
require 'chrono_model/patches'
require 'chrono_model/time_machine'
require 'chrono_model/time_gate'
require 'chrono_model/utils'

module ChronoModel
  class Error < ActiveRecord::ActiveRecordError #:nodoc:
  end

  def self.upgrade!
    connection = ActiveRecord::Base.connection

    unless connection.is_a?(ChronoModel::Adapter)
      raise ChronoModel::Error, "This database connection is not a ChronoModel::Adapter"
    end

    connection.chrono_upgrade!
  end
end

if defined?(Rails)
  require 'chrono_model/railtie'
end

ActiveRecord::Associations::Association.instance_eval do
  prepend ChronoModel::Patches::Association
end

ActiveRecord::Relation.instance_eval do
  prepend ChronoModel::Patches::Relation
end

ActiveRecord::Associations::Preloader.instance_eval do
  prepend ChronoModel::Patches::Preloader
end

ActiveRecord::Associations::Preloader::Association.instance_eval do
  prepend ChronoModel::Patches::Preloader::Association
end
