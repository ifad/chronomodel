# frozen_string_literal: true

module ChronoModel
  module Patches
    module Relation
      include ChronoModel::Patches::AsOfTimeHolder

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

      def empty_scope?
        return super unless @_as_of_time

        @values == klass.unscoped.as_of(as_of_time).values
      end

      def load(&block)
        return super unless @_as_of_time && (!loaded? || scheduled?)

        records = super

        records.each do |record|
          record.as_of_time!(@_as_of_time)
          propagate_as_of_time_to_includes(record)
        end

        self
      end

      def merge(*)
        return super unless @_as_of_time

        super.as_of_time!(@_as_of_time)
      end

      def find_nth(*)
        return super unless try(:history?)

        with_hid_pkey { super }
      end

      def last(*)
        return super unless try(:history?)

        with_hid_pkey { super }
      end

      private

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

      def ordered_relation
        return super unless try(:history?)

        with_hid_pkey { super }
      end

      # Propagate as_of_time to associations that were eager loaded via includes/eager_load
      def propagate_as_of_time_to_includes(record)
        return unless eager_loading?

        assign_as_of_time_to_spec(record, includes_values)
      end

      def assign_as_of_time_to_spec(record, spec)
        case spec
        when Symbol, String
          assign_as_of_time_to_association(record, spec.to_sym, nil)
        when Array
          spec.each { |s| assign_as_of_time_to_spec(record, s) }
        when Hash
          # This branch is difficult to trigger in practice due to Rails query optimization.
          # Modern Rails versions tend to optimize eager loading in ways that make this specific
          # code path challenging to reproduce in tests without artificial scenarios.
          spec.each do |name, nested|
            assign_as_of_time_to_association(record, name.to_sym, nested)
          end
        end
      end

      def assign_as_of_time_to_association(record, name, nested)
        reflection = record.class.reflect_on_association(name)
        return unless reflection

        assoc = record.association(name)
        return unless assoc.loaded?

        target = assoc.target

        if target.is_a?(Array)
          target.each { |t| t.respond_to?(:as_of_time!) && t.as_of_time!(@_as_of_time) }
          # This nested condition is difficult to trigger in practice as it requires specific
          # association loading scenarios with Array targets and nested specs that Rails
          # query optimization tends to handle differently in modern versions.
          if nested.present?
            target.each { |t| assign_as_of_time_to_spec(t, nested) }
          end
        else
          target.respond_to?(:as_of_time!) && target.as_of_time!(@_as_of_time)
          assign_as_of_time_to_spec(target, nested) if nested.present? && target
        end
      end
    end
  end
end
