require 'chrono_model/version'
require 'chrono_model/adapter'
require 'chrono_model/compatibility'
require 'chrono_model/patches'
require 'chrono_model/time_machine'

module ChronoModel
  class Error < ActiveRecord::ActiveRecordError #:nodoc:
  end
end

# Install it.
silence_warnings do
  # Replace AR's PG adapter with the ChronoModel one. This (dirty) approach is
  # required because the PG adapter defines +add_column+ itself, thus making
  # impossible to use super() in overridden Module methods.
  #
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter = ChronoModel::Adapter

  # We need to override the "scoped" method on AR::Association for temporal
  # associations to work as well
  ActiveRecord::Associations::Association = ChronoModel::Patches::Association

  # This implements correct WITH syntax on PostgreSQL
  Arel::Visitors::PostgreSQL = ChronoModel::Patches::Visitor

  # This adds .with support to ActiveRecord::Relation
  ActiveRecord::Relation.instance_eval { include ChronoModel::Patches::QueryMethods }
  ActiveRecord::Base.extend ChronoModel::Patches::Querying
end
