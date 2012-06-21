module ChronoTest::Helpers

  module Adapter
    def self.included(base)
      base.extend DSL
    end

    def adapter
      ChronoTest.connection
    end

    def columns
      DSL.columns
    end

    module DSL
      def with_temporal_table(&block)
        context ':temporal => true' do
          before(:all) { adapter.create_table(table, :temporal => true, &columns) }
          after(:all)  { adapter.drop_table table }

          instance_eval(&block)
        end
      end

      def with_plain_table(&block)
        context ':temporal => false' do
          before(:all) { adapter.create_table(table, :temporal => false, &columns) }
          after(:all)  { adapter.drop_table table }

          instance_eval(&block)
        end
      end

      def columns(&block)
        DSL.columns = block.call
      end

      class << self
        attr_accessor :columns
      end
    end
  end

end
