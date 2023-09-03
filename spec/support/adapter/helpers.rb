module ChronoTest
  module Adapter
  module Helpers
    def self.included(base)
      base.extend DSL

      base.instance_eval do
        delegate :adapter, to: ChronoTest
        delegate :columns, :table, :pk_type, to: DSL
      end
    end

    module DSL
      def with_temporal_table(&block)
        context ':temporal => true' do
          before(:all) { adapter.create_table(table, temporal: true, &DSL.columns) }
          after(:all)  { adapter.drop_table table }

          instance_eval(&block)
        end
      end

      def with_plain_table(&block)
        context ':temporal => false' do
          before(:all) { adapter.create_table(table, temporal: false, &DSL.columns) }
          after(:all)  { adapter.drop_table table }

          instance_eval(&block)
        end
      end

      def self.table(table = nil)
        @table = table if table
        @table
      end

      def self.columns(&block)
        @columns = yield if block
        @columns
      end

      def self.pk_type
        @pk_type ||= if ActiveRecord::VERSION::STRING.to_f >= 5.1
                       'bigint'
        else
          'integer'
        end
      end
      delegate :columns, :table, :pk_type, to: self
    end
  end
  end
end
