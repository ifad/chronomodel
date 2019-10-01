module ChronoTest::Matchers

  module Source
    class HaveFunctionSource < ChronoTest::Matchers::Base
      def initialize(function, source_regexp)
        @function = function
        @regexp   = source_regexp
      end

      def description
        "have function source matching #{@regexp}"
      end

      def matches?(table)
        super(table)

        source = select_value(<<-SQL, [@function], "Get #@function source")
          SELECT prosrc FROM pg_catalog.pg_proc WHERE proname = ?
        SQL

        !(source =~ @regexp).nil?
      end

      def failure_message
        "expected #{table} to have a #{@function} matching #{@regexp}"
      end

      def failure_message_when_negated
        "expected #{table} to not have a #{@function} matching #{@regexp}"
      end
    end

    def have_function_source(*args)
      HaveFunctionSource.new(*args)
    end
  end
end
