require 'support/matchers/base'

module ChronoTest::Matchers

  module Schema
    class BeInSchema < ChronoTest::Matchers::Base

      def initialize(expected)
        @expected = expected
        @expected = '"$user", public' if @expected == :default
      end

      def description
        'be in schema'
      end

      def failure_message_for_should
        "expected to be in schema #@expected, but was in #@current"
      end

      def matches?(*)
        @current = select_value(<<-SQL, [], 'Current schema')
          SHOW search_path
        SQL

        @current == @expected
      end
    end

    def be_in_schema(schema)
      BeInSchema.new(schema)
    end
  end

end
