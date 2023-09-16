module ChronoModel
  module Patches
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

        virtual_table = history_model
                        .virtual_table_at(@as_of_time, table_name: @table_alias || @table_name)

        super(virtual_table)
      end
    end
  end
end
