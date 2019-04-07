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
            # This case happens with nested includes, where the below
            # code has already replaced the join.left with a JoinNode.
            #
            next if join.left.respond_to?(:as_of_time)

            model = ChronoModel.history_models[join.left.table_name]
            next unless model

            join.left = ChronoModel::Patches::JoinNode.new(
              join.left, model.history, @_as_of_time)
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

  end
end
