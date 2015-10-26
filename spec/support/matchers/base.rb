require 'ostruct'

module ChronoTest::Matchers
  class Base
    include ActiveRecord::Sanitization::ClassMethods

    attr_reader :table

    def matches?(table)
      table = table.table_name if table.respond_to?(:table_name)
      @table = table
    end
    private :matches? # This is an abstract class

    def failure_message_for_should_not
      failure_message_for_should.gsub(/to /, 'to not ')
    end

    protected

      def connection
        ChronoTest.connection
      end

      def temporal_schema
        ChronoModel::Adapter::TEMPORAL_SCHEMA
      end

      def history_schema
        ChronoModel::Adapter::HISTORY_SCHEMA
      end

      def public_schema
        'public'
      end

      def select_value(sql, binds, name = nil)
        result = exec_query(sql, binds, name || 'select_value')
        result.rows.first.try(:[], 0)
      end

      def select_values(sql, binds, name = nil)
        result = exec_query(sql, binds, name || 'select_values')
        result.rows.map(&:first)
      end

      def select_rows(sql, binds, name = nil)
        exec_query(sql, binds, name || 'select_rows').rows
      end

    private
      def exec_query(sql, binds, name)
        sql = sanitize_sql([sql, *binds], nil)
        connection.exec_query(sql, name)
      end
  end

end
