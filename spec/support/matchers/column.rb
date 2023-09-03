module ChronoTest
  module Matchers
    module Column
      class HaveColumns < ChronoTest::Matchers::Base
        def initialize(columns, schema = 'public')
          @columns = columns
          @schema  = schema
        end

        def description
          'have columns'
        end

        def matches?(table)
          super(table)

          @matches = @columns.inject({}) do |h, (name, type)|
            h.update([name, type] => has_column?(name, type))
          end

          @matches.values.all?
        end

        def failure_message
          message_matches("expected #{@schema}.#{table} to have")
        end

        def failure_message_when_negated
          message_matches("expected #{@schema}.#{table} to not have")
        end

        protected

        def has_column?(name, type)
          column_type(name) == [name, type]
        end

        def column_type(name)
          table = "#{@schema}.#{self.table}"

          select_rows(<<-SQL, [table, name], 'Check column').first
            SELECT attname, FORMAT_TYPE(atttypid, atttypmod)
              FROM pg_attribute
             WHERE attrelid = ?::regclass::oid
               AND attname = ?
          SQL
        end

        private

        def message_matches(message)
          (message << ' ').tap do |message|
            message << @matches.map do |(name, type), match|
              "a #{name}(#{type}) column" unless match
            end.compact.to_sentence
          end
        end
      end

      def have_columns(*args)
        HaveColumns.new(*args)
      end

      class HaveTemporalColumns < HaveColumns
        def initialize(columns)
          super(columns, temporal_schema)
        end
      end

      def have_temporal_columns(*args)
        HaveTemporalColumns.new(*args)
      end

      class HaveHistoryColumns < HaveColumns
        def initialize(columns)
          super(columns, history_schema)
        end
      end

      def have_history_columns(*args)
        HaveHistoryColumns.new(*args)
      end

      class HaveHistoryExtraColumns < HaveColumns
        def initialize
          super([
            %w[validity tsrange],
            ['recorded_at', 'timestamp without time zone'],
            %w[hid bigint]
          ], history_schema)
        end
      end

      def have_history_extra_columns
        HaveHistoryExtraColumns.new
      end
    end
  end
end
