# frozen_string_literal: true

module ChronoModel
  module Patches
    # Patches ActiveRecord::Relation to add temporal query support.
    #
    # Extends relations with AsOfTimeHolder functionality and modifies
    # various query methods to work correctly with temporal data.
    module Relation
      include ChronoModel::Patches::AsOfTimeHolder

      # Preloads associations with temporal awareness.
      #
      # Modified to pass as_of_time and model information to the preloader
      # for temporal association handling.
      #
      # @param records [Array<ActiveRecord::Base>] records to preload associations for
      # @return [void]
      # @api private
      def preload_associations(records) # :nodoc:
        preload = preload_values
        preload += includes_values unless eager_loading?
        scope = StrictLoadingScope if strict_loading_value

        preload.each do |associations|
          ActiveRecord::Associations::Preloader.new(
            records: records, associations: associations, scope: scope, model: model, as_of_time: as_of_time
          ).call
        end
      end

      # Determines if this relation represents an empty scope.
      #
      # For temporal relations, compares against the model's unscoped as_of relation.
      #
      # @return [Boolean] true if this relation represents an empty scope
      def empty_scope?
        return super unless @_as_of_time

        @values == klass.unscoped.as_of(as_of_time).values
      end

      # Loads records and applies temporal settings to each record.
      #
      # For temporal relations, ensures each loaded record carries the as_of_time
      # information for consistent temporal behavior.
      #
      # @param block [Proc] optional block to yield each record to
      # @return [self] returns self for method chaining
      def load(&block)
        return super unless @_as_of_time && (!loaded? || scheduled?)

        super.each { |record| record.as_of_time!(@_as_of_time) }

        self
      end

      # Merges this relation with another, preserving temporal settings.
      #
      # @param other [ActiveRecord::Relation] the relation to merge with
      # @return [ActiveRecord::Relation] the merged relation with temporal settings preserved
      def merge(*)
        return super unless @_as_of_time

        super.as_of_time!(@_as_of_time)
      end

      # Finds the nth record, using correct primary key for historical models.
      #
      # @param args [Array] arguments passed to find_nth
      # @return [ActiveRecord::Base, nil] the found record or nil
      def find_nth(*)
        return super unless try(:history?)

        with_hid_pkey { super }
      end

      # Finds the last record(s), using correct primary key for historical models.
      #
      # @param args [Array] arguments passed to last
      # @return [ActiveRecord::Base, Array<ActiveRecord::Base>, nil] the last record(s) or nil
      def last(*)
        return super unless try(:history?)

        with_hid_pkey { super }
      end

      private

      # Builds the Arel AST with temporal join modifications.
      #
      # For temporal relations, replaces join sources with temporal-aware
      # versions that query historical data at the specified time.
      #
      # @param args [Array] arguments passed to build_arel
      # @return [Arel::SelectManager] the Arel AST with temporal modifications
      # @api private
      def build_arel(*)
        return super unless @_as_of_time

        super.tap do |arel|
          arel.join_sources.each do |join|
            chrono_join_history(join)
          end
        end
      end

      # Replaces a join with the current data with another that
      # loads records As-Of time against the history data.
      #
      # @param join [Arel::Nodes::Join] the join node to potentially replace
      # @return [void]
      # @api private
      def chrono_join_history(join)
        # This case happens with nested includes, where the below
        # code has already replaced the join.left with a JoinNode.
        #
        return if join.left.respond_to?(:as_of_time)

        model =
          if join.left.respond_to?(:table_name)
            ChronoModel.history_models[join.left.table_name]
          else
            ChronoModel.history_models[join.left]
          end

        return unless model

        join.left = ChronoModel::Patches::JoinNode.new(
          join.left, model.history, @_as_of_time
        )
      end

      # Returns an ordered relation using the correct primary key for historical models.
      #
      # @return [ActiveRecord::Relation] the ordered relation
      # @api private
      def ordered_relation
        return super unless try(:history?)

        with_hid_pkey { super }
      end
    end
  end
end
