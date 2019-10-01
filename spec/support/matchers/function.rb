module ChronoTest::Matchers

  module Function
    class HaveFunctions < ChronoTest::Matchers::Base
      def initialize(functions, schema = 'public')
        @functions = functions
        @schema    = schema
      end

      def description
        'have functions'
      end

      def matches?(table)
        super(table)

        @matches = @functions.inject({}) do |h, name|
          h.update(name => has_function?(name))
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
        def has_function?(name)
          select_value(<<-SQL, [name], 'Check function') == true
            SELECT EXISTS(
              SELECT 1
              FROM pg_catalog.pg_proc p, pg_catalog.pg_namespace n
              WHERE p.pronamespace = n.oid
                AND n.nspname = 'public'
                AND p.proname = ?
            )
          SQL
        end

      private
        def message_matches(message)
          (message << ' ').tap do |message|
            message << @matches.map do |name, match|
              "a #{name} function"
            end.compact.to_sentence
          end
        end
    end

    def have_functions(*args)
      HaveFunctions.new(*args)
    end

    class HaveHistoryFunctions < HaveFunctions
      def initialize
        @function_templates = [
          'chronomodel_%s_insert',
          'chronomodel_%s_update',
          'chronomodel_%s_delete',
        ]
      end

      def matches?(table)
        @functions = @function_templates.map {|t| t % [table] }

        super(table)
      end
    end

    def have_history_functions
      HaveHistoryFunctions.new
    end
  end
end
