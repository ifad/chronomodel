module ChronoTest::Helpers

  module Adapter
    def self.included(base)
      base.extend DSL
      base.instance_eval do
        delegate :adapter, :to => ChronoTest
        delegate :columns, :table, :pk_type, :to => DSL
      end
    end

    module DSL
      def with_temporal_table(&block)
        context ':temporal => true' do
          before(:all) { adapter.create_table(table, :temporal => true, &DSL.columns) }
          after(:all)  { adapter.drop_table table }

          instance_eval(&block)
        end
      end

      def with_plain_table(&block)
        context ':temporal => false' do
          before(:all) { adapter.create_table(table, :temporal => false, &DSL.columns) }
          after(:all)  { adapter.drop_table table }

          instance_eval(&block)
        end
      end

      def self.table(table = nil)
        @table = table if table
        @table
      end

      def self.columns(&block)
        @columns = block.call if block
        @columns
      end

      def self.pk_type
        @pk_type ||= if ActiveRecord::VERSION::MAJOR == 5 && ActiveRecord::VERSION::MINOR >= 1
          'bigint'
        else
          'integer'
        end
      end
      delegate :columns, :table, :pk_type, :to => self
    end
  end

  module TimeMachine
    def self.included(base)
      base.extend(DSL)
      base.extend(self)
    end

    module DSL
      @@schema_setup = false

      def setup_schema!
        return if @@schema_setup
        @@schema_setup = true

        # Set up database structure
        #
        adapter.create_table 'foos', :temporal => true do |t|
          t.string     :name
          t.integer    :fooity
        end

        adapter.create_table 'bars', :temporal => true do |t|
          t.string     :name
          t.references :foo
        end

        adapter.create_table 'sub_bars', :temporal => true do |t|
          t.string     :name
          t.references :bar
        end

        adapter.create_table 'bazs' do |t|
          t.string     :name
          t.references :bar
        end

        adapter.create_table 'defoos', :temporal => true do |t|
          t.string  :name
          t.boolean :active
        end

        adapter.create_table 'elements', :temporal => true do |t|
          t.string :title
          t.string :type
        end

        adapter.create_table 'plains' do |t|
          t.string :foo
        end

        adapter.create_table 'events' do |t|
          t.string :name
          t.daterange :interval
        end

        adapter.create_table 'sections', :temporal => true do |t|
          t.string :name
          t.integer :articles_count, default: 0
        end

        adapter.create_table 'articles', :temporal => true do |t|
          t.string :title
          t.references :section
        end

      end

      Models = lambda {
        class ::Foo < ActiveRecord::Base
          include ChronoModel::TimeMachine

          has_many :bars
          has_many :sub_bars, :through => :bars
        end

        class ::Bar < ActiveRecord::Base
          include ChronoModel::TimeMachine

          belongs_to :foo
          has_many :sub_bars
          has_one :baz

          has_timeline :with => :foo
        end

        class ::SubBar < ActiveRecord::Base
          include ChronoModel::TimeMachine

          belongs_to :bar

          has_timeline :with => :bar
        end

        class ::Baz < ActiveRecord::Base
          include ChronoModel::TimeGate

          belongs_to :bar

          has_timeline :with => :bar
        end

        class ::Defoo < ActiveRecord::Base
          include ChronoModel::TimeMachine

          default_scope proc { where(:active => true) }
        end

        # STI case (https://github.com/ifad/chronomodel/issues/5)
        class ::Element < ActiveRecord::Base
          include ChronoModel::TimeMachine
        end

        class ::Publication < Element
        end

        class ::Plain < ActiveRecord::Base
        end

        class ::Event < ActiveRecord::Base
          extend ChronoModel::TimeMachine::TimeQuery
        end

        class ::Section < ActiveRecord::Base
          include ChronoModel::TimeMachine

          has_many :articles
        end

        class ::Article < ActiveRecord::Base
          include ChronoModel::TimeMachine

          belongs_to :section, counter_cache: true
        end

      }

      @@models_defined = false
      def define_models!
        return if @@models_defined
        @@models_defined = true

        Models.call
      end

      def adapter
        ChronoTest.connection
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

        now = ChronoTest.connection.select_value('select now()::timestamp') + 'Z'
        obj.ts.push(Time.parse(now))
      end
    end
  end

end
