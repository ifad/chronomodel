module ChronoModel
  module Patches

    module Relation
      include ChronoModel::Patches::AsOfTimeHolder

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

        if (join.left.respond_to?(:table_name))
          model = ChronoModel.history_models[join.left.table_name]
        else
          model = ChronoModel.history_models[join.left]
        end
        return unless model

        join.left = ChronoModel::Patches::JoinNode.new(
          join.left, model.history, @_as_of_time)
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

  end
end
