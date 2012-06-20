module ChronoTest::Matchers

  module Column
    class HaveColumns < ChronoTest::Matchers::Base
      def initialize(columns, schema = 'public')
        @columns = columns
        @schema  = schema
      end

      def matches?(table)
        super(table)

        @matches = @columns.inject({}) do |h, (name, type)|
          h.update([name, type] => has_column?(name, type))
        end

        @matches.values.all?
      end

      def failure_message_for_should
        "expected #{@schema}.#{table} to have ".tap do |message|
          message << @matches.map do |(name, type), match|
            "a #{name}(#{type}) column" unless match
          end.compact.to_sentence
        end
      end

      protected
        def has_column?(name, type)
          table = "#{@schema}.#{self.table}"

          select_rows(<<-SQL, [table, name], 'Check column').first == [name, type]
            SELECT attname, FORMAT_TYPE(atttypid, atttypmod)
              FROM pg_attribute
             WHERE attrelid = $1::regclass::oid
               AND attname = $2
          SQL
        end
    end

    def have_columns(*args)
      HaveColumns.new(*args)
    end


    class HaveHistoryColumns < HaveColumns
      def initialize
        super([
          ['valid_from',  'timestamp without time zone'],
          ['valid_to',    'timestamp without time zone'],
          ['recorded_at', 'timestamp without time zone'],
          ['hid',         'integer']
        ], history_schema)
      end
    end

    def have_history_columns
      HaveHistoryColumns.new
    end
  end
end
