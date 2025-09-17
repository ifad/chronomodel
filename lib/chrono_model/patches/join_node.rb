# frozen_string_literal: true

module ChronoModel
  module Patches
    # This class supports the AR < 7.1 code that expects to receive an
    # Arel::Table as the left join node. We need to replace the node
    # with a virtual table that fetches from the history at a given
    # point in time, we replace the join node with a SqlLiteral node
    # that does not respond to the methods that AR expects.
    #
    # This class provides AR with an object implementing the methods
    # it expects, yet producing SQL that fetches from history tables
    # as-of-time.
    #
    # TODO: Remove when dropping Rails < 7.1 compatibility
    class JoinNode < Arel::Nodes::SqlLiteral
      attr_reader :name, :table_name, :table_alias, :as_of_time

      def initialize(join_node, history_model, as_of_time)
        table_name = self.class.table_name_for(join_node)

        @name        = table_name
        @table_name  = table_name
        @table_alias = join_node.table_alias if join_node.respond_to?(:table_alias)

        @as_of_time  = as_of_time

        virtual_table = history_model
                        .virtual_table_at(@as_of_time, table_name: @table_alias || @table_name)

        super(virtual_table)
      end

      class << self
        # Handle both Arel::Table (which has .name method) and other join node types
        # (which have .table_name method) to extract the table name consistently
        def table_name_for(join_node)
          if join_node.respond_to?(:table_name)
            join_node.table_name
          elsif join_node.respond_to?(:name)
            join_node.name
          else
            raise ArgumentError, "Cannot determine table name from #{join_node.class}: expected :table_name or :name method"
          end
        end

        def history_model_for(join_node)
          if join_node.respond_to?(:table_name)
            ChronoModel.history_models[join_node.table_name]
          elsif join_node.respond_to?(:name)
            ChronoModel.history_models[join_node.name]
          end
        end
      end
    end
  end
end
