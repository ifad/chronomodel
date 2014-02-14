require 'chrono_model/version'
require 'chrono_model/adapter'
require 'chrono_model/patches'
require 'chrono_model/time_machine'
require 'chrono_model/time_gate'
require 'chrono_model/utils'

module ChronoModel
  class Error < ActiveRecord::ActiveRecordError #:nodoc:
  end
end

if defined?(Rails)
  require 'chrono_model/railtie'
end

silence_warnings do
  # We need to override the "scoped" method on AR::Association for temporal
  # associations to work as well
  ActiveRecord::Associations::Association = ChronoModel::Patches::Association
end
