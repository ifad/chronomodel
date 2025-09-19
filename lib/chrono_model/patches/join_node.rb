# frozen_string_literal: true

module ChronoModel
  module Patches
    # Replaces the left side of an Arel join (table or table alias) with a SQL
    # literal pointing to the history virtual table at the given as_of_time,
    # preserving any existing table alias.
    class JoinNode < Arel::Nodes::SqlLiteral
      attr_reader :as_of_time

      def initialize(join_node, history_model, as_of_time)
        @as_of_time  = as_of_time

        table_name = join_node.table_alias || join_node.name
        virtual_table = history_model.virtual_table_at(@as_of_time, table_name: table_name)

        super(virtual_table)
      end
    end
  end
end
