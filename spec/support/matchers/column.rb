module ChronoTest::Matchers

  module Column
    class Base < ChronoTest::Matchers::Base
      protected
        def has_column?(options)
          schema, name, type = options.values_at(:in, :name, :type)
          table = "#{schema}.#{self.table}"

          select_rows(<<-SQL, [table, name], 'Check column').first == [name, type]
            SELECT attname, FORMAT_TYPE(atttypid, atttypmod)
              FROM pg_attribute
             WHERE attrelid = $1::regclass::oid
               AND attname = $2
          SQL
        end
    end

    class HaveHistoryColumns < Base
      def matches?(table)
        super(table)

        columns = [
          ['valid_from',  'timestamp without time zone'],
          ['valid_to',    'timestamp without time zone'],
          ['recorded_at', 'timestamp without time zone'],
          ['hid',         'integer']
        ]

        @matches = columns.inject({}) do |h, (name, type)|
          h.update([name, type] => has_column?(name, type))
        end

        @matches.values.all?
      end

      def failure_message_for_should
        "expected #{history_schema}.#{table} to have ".tap do |message|
          message << @matches.map do |(name, type), match|
            "a #{name}(#{type}) column" unless match
          end.compact.to_sentence
        end
      end

      private
        def has_column?(name, type)
          super(:name => name, :type => type, :in => history_schema)
        end
    end

    def have_history_columns
      HaveHistoryColumns.new
    end
  end
end
