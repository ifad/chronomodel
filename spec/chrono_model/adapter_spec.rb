require 'spec_helper'
require 'support/helpers/adapter'

shared_examples_for 'temporal table' do
  it { expect(adapter.is_chrono?(subject)).to be(true) }

  it { is_expected.to_not have_public_backing }

  it { is_expected.to have_temporal_backing }
  it { is_expected.to have_history_backing }
  it { is_expected.to have_history_extra_columns }
  it { is_expected.to have_history_functions }
  it { is_expected.to have_public_interface }

  it { is_expected.to have_columns(columns) }
  it { is_expected.to have_temporal_columns(columns) }
  it { is_expected.to have_history_columns(columns) }
end

shared_examples_for 'plain table' do
  it { expect(adapter.is_chrono?(subject)).to be(false) }

  it { is_expected.to have_public_backing }

  it { is_expected.to_not have_temporal_backing }
  it { is_expected.to_not have_history_backing }
  it { is_expected.to_not have_history_functions }
  it { is_expected.to_not have_public_interface }

  it { is_expected.to have_columns(columns) }
end

describe ChronoModel::Adapter do
  include ChronoTest::Helpers::Adapter

  context do
    subject { adapter }
    it { is_expected.to be_a_kind_of(ChronoModel::Adapter) }

    context do
      subject { adapter.adapter_name }
      it { is_expected.to eq 'PostgreSQL' }
    end

    context do
      before { expect(adapter).to receive(:postgresql_version).and_return(90300) }
      it { is_expected.to be_chrono_supported }
    end

    context do
      before { expect(adapter).to receive(:postgresql_version).and_return(90000) }
      it { is_expected.to_not be_chrono_supported }
    end
  end

  table 'test_table'
  subject { table }

  columns do
    native = [
      ['test', 'character varying'],
      ['foo',  'integer'],
      ['bar',  'double precision'],
      ['baz',  'text']
    ]

    def native.to_proc
      proc {|t|
        t.string  :test, :null => false, :default => 'default-value'
        t.integer :foo
        t.float   :bar
        t.text    :baz
        t.integer :ary, :array => true, :null => false, :default => []
        t.boolean :bool, :null => false, :default => false
      }
    end

    native
  end

  describe '.is_chrono?' do
    with_temporal_table do
      it { expect(adapter.is_chrono?(table)).to be(true) }
    end

    with_plain_table do
      it { expect(adapter.is_chrono?(table)).to be(false) }
    end

    context 'when schemas are not there yet' do
      before(:all) do
        adapter.execute 'BEGIN'
        adapter.execute 'DROP SCHEMA temporal CASCADE'
        adapter.execute 'DROP SCHEMA history CASCADE'
        adapter.execute 'CREATE TABLE test_table (id integer)'
      end

      after(:all) do
        adapter.execute 'ROLLBACK'
      end

      it { expect { adapter.is_chrono?(table) }.to_not raise_error }

      it { expect(adapter.is_chrono?(table)).to be(false) }
    end
  end

  describe '.create_table' do
    with_temporal_table do
      it_should_behave_like 'temporal table'
    end

    with_plain_table do
      it_should_behave_like 'plain table'
    end
  end

  describe '.rename_table' do
    renamed = 'foo_table'
    subject { renamed }

    context ':temporal => true' do
      before :all do
        adapter.create_table table, :temporal => true, &columns
        adapter.add_index table, :test
        adapter.add_index table, [:foo, :bar]

        adapter.rename_table table, renamed
      end
      after(:all) { adapter.drop_table(renamed) }

      it_should_behave_like 'temporal table'

      it 'renames indexes' do
        new_index_names = adapter.indexes(renamed).map(&:name)
        expected_index_names = [[:test], [:foo, :bar]].map do |idx_cols|
          "index_#{renamed}_on_#{idx_cols.join('_and_')}"
        end
        expect(new_index_names.to_set).to eq expected_index_names.to_set
      end
    end

    context ':temporal => false' do
      before :all do
        adapter.create_table table, :temporal => false, &columns

        adapter.rename_table table, renamed
      end
      after(:all) { adapter.drop_table(renamed) }

      it_should_behave_like 'plain table'
    end
  end

  describe '.change_table' do
    with_temporal_table do
      before :all do
        adapter.change_table table, :temporal => false
      end

      it_should_behave_like 'plain table'
    end

    with_plain_table do
      before :all do
        adapter.add_index table, :foo
        adapter.add_index table, :bar, :unique => true

        adapter.change_table table, :temporal => true
      end

      it_should_behave_like 'temporal table'

      let(:history_indexes) do
        adapter.on_schema(ChronoModel::Adapter::HISTORY_SCHEMA) do
          adapter.indexes(table)
        end
      end

      it "copies plain index to history" do
        expect(history_indexes.find {|i| i.columns == ['foo']}).to be_present
      end

      it "copies unique index to history without uniqueness constraint" do
        expect(history_indexes.find {|i| i.columns == ['bar'] && i.unique == false}).to be_present
      end
    end
  end

  describe '.drop_table' do
    before :all do
      adapter.create_table table, :temporal => true, &columns

      adapter.drop_table table
    end

    it { is_expected.to_not have_public_backing }
    it { is_expected.to_not have_temporal_backing }
    it { is_expected.to_not have_history_backing }
    it { is_expected.to_not have_history_functions }
    it { is_expected.to_not have_public_interface }
  end

  describe '.add_index' do
    with_temporal_table do
      before :all do
        adapter.add_index table, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index table, [:test],      :name => 'test_index'
      end

      it { is_expected.to have_temporal_index 'foobar_index', %w( foo bar ) }
      it { is_expected.to have_history_index  'foobar_index', %w( foo bar ) }
      it { is_expected.to have_temporal_index 'test_index',   %w( test ) }
      it { is_expected.to have_history_index  'test_index',   %w( test ) }

      it { is_expected.to_not have_index 'foobar_index', %w( foo bar ) }
      it { is_expected.to_not have_index 'test_index',   %w( test ) }
    end

    with_plain_table do
      before :all do
        adapter.add_index table, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index table, [:test],      :name => 'test_index'
      end

      it { is_expected.to_not have_temporal_index 'foobar_index', %w( foo bar ) }
      it { is_expected.to_not have_history_index  'foobar_index', %w( foo bar ) }
      it { is_expected.to_not have_temporal_index 'test_index',   %w( test ) }
      it { is_expected.to_not have_history_index  'test_index',   %w( test ) }

      it { is_expected.to have_index 'foobar_index', %w( foo bar ) }
      it { is_expected.to have_index 'test_index',   %w( test ) }
    end
  end

  describe '.remove_index' do
    with_temporal_table do
      before :all do
        adapter.add_index table, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index table, [:test],      :name => 'test_index'

        adapter.remove_index table, :name => 'test_index'
      end

      it { is_expected.to_not have_temporal_index 'test_index', %w( test ) }
      it { is_expected.to_not have_history_index  'test_index', %w( test ) }
      it { is_expected.to_not have_index          'test_index', %w( test ) }
    end

    with_plain_table do
      before :all do
        adapter.add_index table, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index table, [:test],      :name => 'test_index'

        adapter.remove_index table, :name => 'test_index'
      end

      it { is_expected.to_not have_temporal_index 'test_index', %w( test ) }
      it { is_expected.to_not have_history_index  'test_index', %w( test ) }
      it { is_expected.to_not have_index          'test_index', %w( test ) }
    end
  end

  describe '.add_column' do
    let(:extra_columns) { [['foobarbaz', 'integer']] }

    with_temporal_table do
      before :all do
        adapter.add_column table, :foobarbaz, :integer
      end

      it { is_expected.to have_columns(extra_columns) }
      it { is_expected.to have_temporal_columns(extra_columns) }
      it { is_expected.to have_history_columns(extra_columns) }
    end

    with_plain_table do
      before :all do
        adapter.add_column table, :foobarbaz, :integer
      end

      it { is_expected.to have_columns(extra_columns) }
    end
  end

  describe '.remove_column' do
    let(:resulting_columns) { columns.reject {|c,_| c == 'foo'} }

    with_temporal_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.to have_columns(resulting_columns) }
      it { is_expected.to have_temporal_columns(resulting_columns) }
      it { is_expected.to have_history_columns(resulting_columns) }

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_temporal_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_history_columns([['foo', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.to have_columns(resulting_columns) }
      it { is_expected.to_not have_columns([['foo', 'integer']]) }
    end
  end

  describe '.rename_column' do
    with_temporal_table do
      before :all do
        adapter.rename_column table, :foo, :taratapiatapioca
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_temporal_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_history_columns([['foo', 'integer']]) }

      it { is_expected.to have_columns([['taratapiatapioca', 'integer']]) }
      it { is_expected.to have_temporal_columns([['taratapiatapioca', 'integer']]) }
      it { is_expected.to have_history_columns([['taratapiatapioca', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.rename_column table, :foo, :taratapiatapioca
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to have_columns([['taratapiatapioca', 'integer']]) }
    end
  end

  describe '.change_column' do
    with_temporal_table do
      before :all do
        adapter.change_column table, :foo, :float
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_temporal_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_history_columns([['foo', 'integer']]) }

      it { is_expected.to have_columns([['foo', 'double precision']]) }
      it { is_expected.to have_temporal_columns([['foo', 'double precision']]) }
      it { is_expected.to have_history_columns([['foo', 'double precision']]) }
    end

    with_plain_table do
      before(:all) do
        adapter.change_column table, :foo, :float
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to have_columns([['foo', 'double precision']]) }
    end
  end

  describe '.remove_column' do
    with_temporal_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_temporal_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_history_columns([['foo', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
    end
  end

  describe '.column_definitions' do
    subject { adapter.column_definitions(table).map {|d| d.take(2)} }

    assert = proc do
      it { expect(subject & columns).to eq columns }
      it { is_expected.to include(['id', pk_type]) }
    end

    with_temporal_table(&assert)
    with_plain_table(   &assert)
  end

  describe '.primary_key' do
    subject { adapter.primary_key(table) }

    assert = proc do
      it { is_expected.to eq 'id' }
    end

    with_temporal_table(&assert)
    with_plain_table(   &assert)
  end

  describe '.indexes' do
    subject { adapter.indexes(table) }

    assert = proc do
      before(:all) do
        adapter.add_index table, :foo,         :name => 'foo_index'
        adapter.add_index table, [:bar, :baz], :name => 'bar_index'
      end

      it { expect(subject.map(&:name)).to match_array %w( foo_index bar_index ) }
      it { expect(subject.map(&:columns)).to match_array [['foo'], ['bar', 'baz']] }
    end

    with_temporal_table(&assert)
    with_plain_table(   &assert)
  end

  describe '.on_schema' do
    before(:all) do
      adapter.execute 'BEGIN'
      5.times {|i| adapter.execute "CREATE SCHEMA test_#{i}"}
    end

    after(:all) do
      adapter.execute 'ROLLBACK'
    end

    context 'by default' do
      it 'saves the schema at each recursion' do
        is_expected.to be_in_schema(:default)

        adapter.on_schema('test_1') { is_expected.to be_in_schema('test_1')
          adapter.on_schema('test_2') { is_expected.to be_in_schema('test_2')
            adapter.on_schema('test_3') { is_expected.to be_in_schema('test_3')
            }
            is_expected.to be_in_schema('test_2')
          }
          is_expected.to be_in_schema('test_1')
        }

        is_expected.to be_in_schema(:default)
      end

      context 'when errors occur' do
        subject do
          adapter.on_schema('test_1') do

            adapter.on_schema('test_2') do
              adapter.execute 'BEGIN'
              adapter.execute 'ERRORING ON PURPOSE'
            end

          end
        end

        it {
          expect { subject }.
            to raise_error(/current transaction is aborted/).
            and change { adapter.instance_variable_get(:@schema_search_path) }
        }

        after do
          adapter.execute 'ROLLBACK'
        end
      end
    end

    context 'with recurse: :ignore' do
      it 'ignores recursive calls' do
        is_expected.to be_in_schema(:default)

        adapter.on_schema('test_1', recurse: :ignore) { is_expected.to be_in_schema('test_1')
          adapter.on_schema('test_2', recurse: :ignore) { is_expected.to be_in_schema('test_1')
            adapter.on_schema('test_3', recurse: :ignore) { is_expected.to be_in_schema('test_1')
        } } }

        is_expected.to be_in_schema(:default)
      end
    end
  end

  context 'migration extensions' do
    before :all do
      adapter.create_table :meetings do |t|
        t.string :name
        t.tsrange :interval
      end
    end

    after :all do
      adapter.drop_table :meetings
    end

    describe '.add_temporal_indexes' do
      before do
        adapter.add_temporal_indexes :meetings, :interval
      end

      it { expect(adapter.indexes(:meetings).map(&:name)).to eq [
        'index_meetings_temporal_on_interval',
        'index_meetings_temporal_on_lower_interval',
        'index_meetings_temporal_on_upper_interval'
      ] }

      after do
        adapter.remove_temporal_indexes :meetings, :interval
      end
    end

    describe '.remove_temporal_indexes' do
      before :all do
        adapter.add_temporal_indexes :meetings, :interval
      end

      before do
        adapter.remove_temporal_indexes :meetings, :interval
      end

      it { expect(adapter.indexes(:meetings)).to be_empty }
    end

    describe '.add_timeline_consistency_constraint' do
      before do
        adapter.add_timeline_consistency_constraint(:meetings, :interval)
      end

      it { expect(adapter.indexes(:meetings).map(&:name)).to eq [
        'meetings_timeline_consistency'
      ] }

      after do
        adapter.remove_timeline_consistency_constraint(:meetings)
      end
    end

    describe '.remove_timeline_consistency_constraint' do
      before :all do
        adapter.add_timeline_consistency_constraint :meetings, :interval
      end

      before do
        adapter.remove_timeline_consistency_constraint(:meetings)
      end

      it { expect(adapter.indexes(:meetings)).to be_empty }
    end
  end

  let(:current) { [ChronoModel::Adapter::TEMPORAL_SCHEMA, table].join('.') }
  let(:history) { [ChronoModel::Adapter::HISTORY_SCHEMA,  table].join('.') }

  def count(table)
    adapter.select_value("SELECT COUNT(*) FROM ONLY #{table}").to_i
  end

  def ids(table)
    adapter.select_values("SELECT id FROM ONLY #{table} ORDER BY id")
  end

  context 'INSERT multiple values' do
    before :all do
      adapter.create_table table, :temporal => true, &columns
    end

    after :all do
      adapter.drop_table table
    end

    context 'when succeeding' do
      def insert
        adapter.execute <<-SQL
          INSERT INTO #{table} (test, foo) VALUES
            ('test1', 1),
            ('test2', 2);
        SQL
      end

      it { expect { insert }.to_not raise_error }
      it { expect(count(current)).to eq 2 }
      it { expect(count(history)).to eq 2 }
    end

    context 'when failing' do
      def insert
        adapter.execute <<-SQL
          INSERT INTO #{table} (test, foo) VALUES
            ('test3', 3),
            (NULL,    0);
        SQL
      end

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid) }
      it { expect(count(current)).to eq 2 } # Because the previous
      it { expect(count(history)).to eq 2 } # records are preserved
    end

    context 'after a failure' do
      def insert
        adapter.execute <<-SQL
          INSERT INTO #{table} (test, foo) VALUES
            ('test4', 3),
            ('test5', 4);
        SQL
      end

      it { expect { insert }.to_not raise_error }

      it { expect(count(current)).to eq 4 }
      it { expect(count(history)).to eq 4 }

      it { expect(ids(current)).to eq ids(history) }
    end
  end

  context 'INSERT on NOT NULL columns but with a DEFAULT value' do
    before :all do
      adapter.create_table table, :temporal => true, &columns
    end

    after :all do
      adapter.drop_table table
    end

    def insert
      adapter.execute <<-SQL
        INSERT INTO #{table} DEFAULT VALUES
      SQL
    end

    def select
      adapter.select_values <<-SQL
        SELECT test FROM #{table}
      SQL
    end

    it { expect { insert }.to_not raise_error }
    it { insert; expect(select.uniq).to eq ['default-value'] }
  end

  context 'redundant UPDATEs' do

    before :all do
      adapter.create_table table, :temporal => true, &columns

      adapter.execute <<-SQL
        INSERT INTO #{table} (test, foo) VALUES ('test1', 1);
      SQL

      adapter.execute <<-SQL
        UPDATE #{table} SET test = 'test2';
      SQL

      adapter.execute <<-SQL
        UPDATE #{table} SET test = 'test2';
      SQL
    end

    after :all do
      adapter.drop_table table
    end

    it { expect(count(current)).to eq 1 }
    it { expect(count(history)).to eq 2 }

  end

  context 'updates on non-journaled fields' do
    before :all do
      adapter.create_table table, :temporal => true do |t|
        t.string 'test'
        t.timestamps null: false
      end

      adapter.execute <<-SQL
        INSERT INTO #{table} (test, created_at, updated_at) VALUES ('test', now(), now());
      SQL

      adapter.execute <<-SQL
        UPDATE #{table} SET test = 'test2', updated_at = now();
      SQL

      2.times do
        adapter.execute <<-SQL # Redundant update with only updated_at change
          UPDATE #{table} SET test = 'test2', updated_at = now();
        SQL

        adapter.execute <<-SQL
          UPDATE #{table} SET updated_at = now();
        SQL
      end
    end

    after :all do
      adapter.drop_table table
    end

    it { expect(count(current)).to eq 1 }
    it { expect(count(history)).to eq 2 }
  end

  context 'selective journaled fields' do
    describe 'basic behaviour' do
      specify do
        adapter.create_table table, :temporal => true, :journal => %w( foo ) do |t|
          t.string 'foo'
          t.string 'bar'
        end

        adapter.execute <<-SQL
          INSERT INTO #{table} (foo, bar) VALUES ('test foo', 'test bar');
        SQL

        adapter.execute <<-SQL
          UPDATE #{table} SET foo = 'test foo', bar = 'no history';
        SQL

        2.times do
          adapter.execute <<-SQL
            UPDATE #{table} SET bar = 'really no history';
          SQL
        end

        expect(count(current)).to eq 1
        expect(count(history)).to eq 1

        adapter.drop_table table
      end
    end

    describe 'schema changes' do
      table 'journaled_things'

      before do
        adapter.create_table table, :temporal => true, :journal => %w( foo ) do |t|
          t.string 'foo'
          t.string 'bar'
          t.string 'baz'
        end
      end

      after do
        adapter.drop_table table
      end

      it 'preserves options upon column change' do
        adapter.change_table table, temporal: true, journal: %w(foo bar)

        adapter.execute <<-SQL
          INSERT INTO #{table} (foo, bar) VALUES ('test foo', 'test bar');
        SQL

        expect(count(current)).to eq 1
        expect(count(history)).to eq 1

        adapter.execute <<-SQL
          UPDATE #{table} SET foo = 'test foo', bar = 'chronomodel';
        SQL

        expect(count(current)).to eq 1
        expect(count(history)).to eq 2
      end

      it 'changes option upon table change' do
        adapter.change_table table, temporal: true, journal: %w(bar)

        adapter.execute <<-SQL
          INSERT INTO #{table} (foo, bar) VALUES ('test foo', 'test bar');
          UPDATE #{table} SET foo = 'test foo', bar = 'no history';
        SQL

        expect(count(current)).to eq 1
        expect(count(history)).to eq 1

        adapter.execute <<-SQL
          UPDATE #{table} SET foo = 'test foo again', bar = 'no history';
        SQL

        expect(count(current)).to eq 1
        expect(count(history)).to eq 1
      end
    end
  end
end
