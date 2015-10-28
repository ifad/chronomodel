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

# We need to override the "scoped" method on AR::Association for temporal
# associations to work. On Ruby 2.0 and up, the Module#prepend comes in
# handy - on Ruby 1.9 we have to hack the inheritance hierarchy.
#

if RUBY_VERSION.to_i >= 2
  ActiveRecord::Associations::Association.instance_eval do
    prepend ChronoModel::Patches::Association
  end

  ActiveRecord::Relation.instance_eval do
    prepend ChronoModel::Patches::Relation
  end
else
  ActiveSupport::Deprecation.warn 'Ruby 1.9 is deprecated. Please update your Ruby <3'

  silence_warnings do
    class ChronoModel::Patches::AssociationPatch < ActiveRecord::Associations::Association
      include ChronoModel::Patches::Association
    end

    ActiveRecord::Associations::Association = ChronoModel::Patches::AssociationPatch

    class ChronoModel::Patches::RelationPatch < ActiveRecord::Relation
      include ChronoModel::Patches::Relation
    end

    ActiveRecord::Relation = ChronoModel::Patches::RelationPatch
  end
end
