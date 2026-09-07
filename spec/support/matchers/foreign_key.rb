# frozen_string_literal: true

require_relative 'base'

module ChronoTest
  module Matchers
    module ForeignKey
      # Checks that a foreign key constraint exists on the given table in the
      # +from_schema+ schema, referencing +to_table+ in the +to_schema+ schema.
      #
      class HaveForeignKey < ChronoTest::Matchers::Base
        attr_reader :to_table, :from_schema, :to_schema

        def initialize(to_table, from_schema: 'public', to_schema: 'public')
          @to_table    = to_table
          @from_schema = from_schema
          @to_schema   = to_schema
        end

        def description
          'have foreign key'
        end

        def matches?(table)
          super

          binds = [table, from_schema, to_table, to_schema]

          select_value(<<~SQL.squish, binds, 'Check foreign key') == true
            SELECT EXISTS (
              SELECT 1
                FROM pg_constraint c
                JOIN pg_class     t  ON t.oid  = c.conrelid
                JOIN pg_namespace n  ON n.oid  = t.relnamespace
                JOIN pg_class     rt ON rt.oid = c.confrelid
                JOIN pg_namespace rn ON rn.oid = rt.relnamespace
               WHERE c.contype = 'f'
                 AND t.relname  = ? AND n.nspname  = ?
                 AND rt.relname = ? AND rn.nspname = ?
            )
          SQL
        end

        def failure_message
          "expected #{from_schema}.#{table} to have a foreign key referencing #{to_schema}.#{to_table}"
        end

        def failure_message_when_negated
          "expected #{from_schema}.#{table} to not have a foreign key referencing #{to_schema}.#{to_table}"
        end
      end

      def have_foreign_key(to_table, from_schema: 'public', to_schema: 'public')
        HaveForeignKey.new(to_table, from_schema: from_schema, to_schema: to_schema)
      end

      def have_temporal_foreign_key(to_table, to_schema: ChronoModel::Adapter::TEMPORAL_SCHEMA)
        HaveForeignKey.new(to_table, from_schema: ChronoModel::Adapter::TEMPORAL_SCHEMA, to_schema: to_schema)
      end

      def have_history_foreign_key(to_table, to_schema: ChronoModel::Adapter::HISTORY_SCHEMA)
        HaveForeignKey.new(to_table, from_schema: ChronoModel::Adapter::HISTORY_SCHEMA, to_schema: to_schema)
      end
    end
  end
end
