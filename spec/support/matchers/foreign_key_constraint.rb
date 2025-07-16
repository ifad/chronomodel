# frozen_string_literal: true

require_relative 'base'

module ChronoTest
  module Matchers
    module ForeignKeyConstraint
      class HaveForeignKeyConstraint < ChronoTest::Matchers::Base
        attr_reader :ref_table, :ref_schema, :schema

        def initialize(ref_table, ref_schema, schema = 'public')
          @ref_table = ref_table
          @ref_schema = ref_schema
          @schema   = schema
        end

        def description
          'have foreign key constraint'
        end

        def matches?(table)
          super

          select_values(<<~SQL.squish, [table, schema, ref_table, ref_schema], 'Check foreign key constraint').any?
            SELECT 1
              FROM pg_constraint c
              JOIN pg_class t ON c.conrelid = t.oid
              JOIN pg_class r ON c.confrelid = r.oid
              JOIN pg_namespace tn ON t.relnamespace = tn.oid
              JOIN pg_namespace rn ON r.relnamespace = rn.oid
            WHERE t.relname = ?
              AND tn.nspname = ?
              AND r.relname = ?
              AND rn.nspname = ?
              AND c.contype = 'f';
          SQL
        end

        def failure_message
          "expected #{schema}.#{table} to have a foreign key constraint on #{ref_schema}#{ref_table}"
        end

        def failure_message_when_negated
          "expected #{schema}.#{table} to not have a foreign key constraint on #{ref_schema}.#{ref_table}"
        end
      end

      def have_foreign_key_constraint(*args)
        HaveForeignKeyConstraint.new(*args)
      end

      class HaveTemporalForeignKeyConstraint < HaveForeignKeyConstraint
        def initialize(ref_table, ref_schema)
          super(ref_table, ref_schema, temporal_schema)
        end
      end

      def have_temporal_foreign_key_constraint(*args)
        HaveTemporalForeignKeyConstraint.new(*args)
      end
    end
  end
end
