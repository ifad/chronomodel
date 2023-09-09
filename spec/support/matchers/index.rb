# frozen_string_literal: true

module ChronoTest
  module Matchers
    module Index
      class HaveIndex < ChronoTest::Matchers::Base
        attr_reader :name, :columns, :schema

        def initialize(name, columns, schema = 'public')
          @name    = name
          @columns = columns.sort
          @schema  = schema
        end

        def description
          'have index'
        end

        def matches?(table)
          super(table)

          select_values(<<-SQL.squish, [table, name, schema], 'Check index') == columns
          SELECT a.attname
            FROM pg_class t
            JOIN pg_index d ON t.oid = d.indrelid
            JOIN pg_class i ON i.oid = d.indexrelid
            JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(d.indkey)
           WHERE i.relkind = 'i'
             AND t.relname = ?
             AND i.relname = ?
             AND i.relnamespace = (
              SELECT oid FROM pg_namespace WHERE nspname = ?
            )
           ORDER BY a.attname
          SQL
        end

        def failure_message
          "expected #{schema}.#{table} to have a #{name} index on #{columns}"
        end

        def failure_message_when_negated
          "expected #{schema}.#{table} to not have a #{name} index on #{columns}"
        end
      end

      def have_index(*args)
        HaveIndex.new(*args)
      end

      class HaveTemporalIndex < HaveIndex
        def initialize(name, columns)
          super(name, columns, temporal_schema)
        end
      end

      def have_temporal_index(*args)
        HaveTemporalIndex.new(*args)
      end

      class HaveHistoryIndex < HaveIndex
        def initialize(name, columns)
          super(name, columns, history_schema)
        end
      end

      def have_history_index(*args)
        HaveHistoryIndex.new(*args)
      end
    end
  end
end
