require 'active_record'

module ChronoModel
  module Patches

    module AsOfTimeHolder
      # Sets the virtual 'as_of_time' attribute to the given time, converting to UTC.
      #
      def as_of_time!(time)
        @_as_of_time = time.utc

        self
      end

      # Reads the virtual 'as_of_time' attribute
      #
      def as_of_time
        @_as_of_time
      end
    end

    # This class supports the AR 5.0 code that expects to receive an
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

      def build_arel(*)
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

      # Build a preloader at the +as_of_time+ of this relation.
      # Pass the current model to define Relation
      #
      def build_preloader
        ActiveRecord::Associations::Preloader.new(
          model: self.model, as_of_time: as_of_time
        )
      end
    end

    # This class is a dummy relation whose scope is only to pass around the
    # as_of_time parameters across ActiveRecord call chains.
    #
    # With AR 5.2 a simple relation can be used, as the only required argument
    # is the model. 5.0 and 5.1 require more arguments, that are passed here.
    #
    class AsOfTimeRelation < ActiveRecord::Relation
      if ActiveRecord::VERSION::STRING.to_f < 5.2
        def initialize(klass, table: klass.arel_table, predicate_builder: klass.predicate_builder, values: {})
          super(klass, table, predicate_builder, values)
        end
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

      # Patches the AR Preloader (lib/active_record/associations/preloader.rb)
      # in order to carry around the +as_of_time+ of the original invocation.
      #
      # * The +records+ are the parent records where the association is defined
      # * The +associations+ are the association names involved in preloading
      # * The +given_preload_scope+ is the preloading scope, that is used only
      #   in the :through association and it holds the intermediate records
      #   _through_ which the final associated records are eventually fetched.
      #
      # As the +preload_scope+ is passed around to all the different
      # incarnations of the preloader strategies, we are using it to pass
      # around the +as_of_time+ of the original query invocation, so that
      # preloaded records are preloaded honoring the +as_of_time+.
      #
      # The +preload_scope+ is present only in through associations, but the
      # preloader interfaces expect it to be always defined, for consistency.
      #
      # For `:through` associations, the +given_preload_scope+ is already a
      # +Relation+, that already has the +as_of_time+ getters and setters,
      # so we use it directly.
      #
      def preload(records, associations, given_preload_scope = nil)
        if options[:as_of_time]
          preload_scope = given_preload_scope ||
            AsOfTimeRelation.new(options[:model])

          preload_scope.as_of_time!(options[:as_of_time])
        end

        super records, associations, preload_scope
      end

      module Association
        # Builds the preloader scope taking into account a potential
        # +as_of_time+ passed down the call chain starting at the
        # end user invocation.
        #
        def build_scope
          scope = super

          if preload_scope.try(:as_of_time)
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
      def skip_statement_cache?(*)
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
