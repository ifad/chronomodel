require 'active_record'

module ChronoModel
  module Patches

    module AsOfTimeHolder
      # Sets the virtual 'as_of_time' attribute to the given time, converting to UTC.
      #
      # See ChronoModel::Patches::AsOfTimeHolder
      #
      def as_of_time!(time)
        @_as_of_time = time.utc

        self
      end

      # Reads the virtual 'as_of_time' attribute
      #
      # See ChronoModel::Patches::AsOfTimeHolder
      #
      def as_of_time
        @_as_of_time
      end
    end

    # This class supports the AR 4.2 code that expects to receive an
    # Arel::Table as the left join node. We need to replace the node
    # with a virtual table that fetches from the history at a given
    # point in time, we replace the join node with a SqlLiteral node
    # that does not respond to the methods that AR expects.
    #
    # This class provides AR with an object implementing the methods
    # it expects, yet producing SQL that fetches from history tables
    # as-of-time.
    #
    class JoinNode < Arel::Nodes::SqlLiteral
      attr_reader :name, :table_name, :table_alias, :as_of_time

      def initialize(join_node, history_model, as_of_time)
        @name        = join_node.table_name
        @table_name  = join_node.table_name
        @table_alias = join_node.table_alias

        @as_of_time  = as_of_time

        virtual_table = history_model.
          virtual_table_at(@as_of_time, @table_alias || @table_name)

        super(virtual_table)
      end
    end

    module Relation
      include AsOfTimeHolder

      def load
        return super unless @_as_of_time && !loaded?

        super.each {|record| record.as_of_time!(@_as_of_time) }
      end

      def merge(*)
        return super unless @_as_of_time

        super.as_of_time!(@_as_of_time)
      end

      def build_arel
        return super unless @_as_of_time

        super.tap do |arel|

          arel.join_sources.each do |join|
            # This case happens with nested includes, where the below
            # code has already replaced the join.left with a JoinNode.
            #
            next if join.left.respond_to?(:as_of_time)

            model = TimeMachine.chrono_models[join.left.table_name]
            next unless model

            join.left = JoinNode.new(join.left, model.history, @_as_of_time)
          end

        end
      end

      # Build a preloader at the +as_of_time+ of this relation
      #
      def build_preloader
        ActiveRecord::Associations::Preloader.new(as_of_time: as_of_time)
      end
    end

    # Patches ActiveRecord::Associations::Preloader to add support for
    # temporal associations. This is tying itself to Rails internals
    # and it is ugly :-(.
    #
    module Preloader
      attr_reader :options

      # We overwrite the initializer in order to pass the +as_of_time+
      # parameter above in the build_preloader
      #
      def initialize(options = {})
        @options = options.freeze
      end

      # See +ActiveRecord::Associations::Preloader::NULL_RELATION+
      NULL_RELATION = ActiveRecord::Associations::Preloader::NULL_RELATION

      # Extension of +NULL_RELATION+ adding an +as_of_time+ property. See
      # +preload+.
      AS_OF_PRELOAD_SCOPE = Struct.new(:as_of_time, *NULL_RELATION.members)

      # Patches the AR Preloader (lib/active_record/associations/preloader.rb)
      # in order to carry around the +as_of_time+ of the original invocation.
      #
      # * The +records+ are the parent records where the association is defined
      # * The +associations+ are the association names involved in preloading
      # * The +given_preload_scope+ is the preloading scope, that is used only
      # in the :through association and it holds the intermediate records
      # _through_ which the final associated records are eventually fetched.
      #
      # As the +preload_scope+ is passed around to all the different
      # incarnations of the preloader strategies, we are using it to pass
      # around the +as_of_time+ of the original query invocation, so that
      # preloaded records are preloaded honoring the +as_of_time+.
      #
      # The +preload_scope+ is not nil only for through associations, but the
      # preloader interfaces expect it to be always defined, for consistency.
      # So, AR defines a +NULL_RELATION+ constant to pass around for the
      # association types that do not have a preload_scope. It quacks like a
      # Relation, and it contains only the methods that are used by the other
      # preloader methods. We extend AR's +NULL_RELATION+ with an `as_of_time`
      # property.
      #
      # For `:through` associations, the +given_preload_scope+ is already a
      # +Relation+, that already has the +as_of_time+ getters and setters,
      # so we use them here.
      #
      def preload(records, associations, given_preload_scope = nil)
        if (as_of_time = options[:as_of_time])
          preload_scope = if given_preload_scope.respond_to?(:as_of_time!)
            given_preload_scope.as_of_time!(as_of_time)
          else
            null_relation_preload_scope(as_of_time, given_preload_scope)
          end
        end

        super records, associations, preload_scope
      end

      private
        def null_relation_preload_scope(as_of_time, given_preload_scope)
          preload_scope = AS_OF_PRELOAD_SCOPE.new

          preload_scope.as_of_time = as_of_time
          given_preload_scope ||= NULL_RELATION

          NULL_RELATION.members.each do |member|
            preload_scope[member] = given_preload_scope[member]
          end

          return preload_scope
        end

      module Association
        # Builds the preloader scope taking into account a potential
        # +as_of_time+ set above in +Preloader#preload+ and coming from the
        # user's query invocation.
        #
        def build_scope
          scope = super

          if preload_scope.respond_to?(:as_of_time)
            scope = scope.as_of(preload_scope.as_of_time)
          end

          return scope
        end
      end
    end

    # Patches ActiveRecord::Associations::Association to add support for
    # temporal associations.
    #
    # Each record fetched from the +as_of+ scope on the owner class will have
    # an additional "as_of_time" field yielding the UTC time of the request,
    # then the as_of scope is called on either this association's class or
    # on the join model's (:through association) one.
    #
    module Association
      def skip_statement_cache?
        super || _chrono_target?
      end

      # If the association class or the through association are ChronoModels,
      # then fetches the records from a virtual table using a subquery scope
      # to a specific timestamp.
      def scope
        scope = super
        return scope unless _chrono_record?

        if _chrono_target?
          # For standard associations, replace the table name with the virtual
          # as-of table name at the owner's as-of-time
          #
          scope = scope.from(klass.history.virtual_table_at(owner.as_of_time))
        elsif respond_to?(:through_reflection) && through_reflection.klass.chrono?

          # For through associations, replace the joined table name instead
          # with a virtual table that selects records from the history at
          # the given +as_of_time+.
          #
          scope.join_sources.each do |join|
            if join.left.name == through_reflection.klass.table_name
              history_model = through_reflection.klass.history

              join.left = JoinNode.new(join.left, history_model, owner.as_of_time)
            end
          end
        end

        scope.as_of_time!(owner.as_of_time)

        return scope
      end

      private
        def _chrono_record?
          owner.respond_to?(:as_of_time) && owner.as_of_time.present?
        end

        def _chrono_target?
          @_target_klass ||= reflection.options[:polymorphic] ?
            owner.public_send(reflection.foreign_type).constantize :
            reflection.klass

          @_target_klass.chrono?
        end

    end

  end
end
