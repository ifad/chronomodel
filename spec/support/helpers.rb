module ChronoTest::Helpers

  module Adapter
    def self.included(base)
      base.let!(:adapter) { ChronoTest.connection }
      base.extend DSL
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

  module TimeMachine
    def self.included(base)
      base.let!(:adapter) { ChronoTest.connection }
      base.extend(DSL)
    end

    module DSL
      def setup_schema!
        # Set up database structure
        #
        before(:all) do
          adapter.create_table 'foos', :temporal => true do |t|
            t.string     :name
            t.integer    :fooity
          end

          adapter.create_table 'bars', :temporal => true do |t|
            t.string     :name
            t.references :foo
          end

          adapter.create_table 'bazs' do |t|
            t.string     :name
            t.references :bar
          end
        end

        after(:all) do
          adapter.drop_table 'foos'
          adapter.drop_table 'bars'
          adapter.drop_table 'bazs'
        end
      end

      Models = lambda {
        class ::Foo < ActiveRecord::Base
          include ChronoModel::TimeMachine

          has_many :bars
        end

        class ::Bar < ActiveRecord::Base
          include ChronoModel::TimeMachine

          belongs_to :foo
          has_one :baz
        end

        class ::Baz < ActiveRecord::Base
          belongs_to :baz
        end
      }

      def define_models!
        before(:all) { Models.call }
      end

    end

    # If a context object is given, evaluates the given
    # block in its instance context, then defines a `ts`
    # on it, backed by an Array, and adds the current
    # database timestamp to it.
    #
    # If a context object is not given, the block is
    # evaluated in the current context and the above
    # mangling is done on the blocks' return value.
    #
    def ts_eval(ctx = nil, &block)
      ret = (ctx || self).instance_eval(&block)
      (ctx || ret).tap do |obj|
        obj.singleton_class.instance_eval do
          define_method(:ts) { @_ts ||= [] }
        end unless obj.methods.include?(:ts)

        now = adapter.select_value('select now()::timestamp')
        obj.ts.push(Time.parse(now))
      end
    end
  end

end
