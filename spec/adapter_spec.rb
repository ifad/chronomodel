require 'spec_helper'
require 'support/helpers'

shared_examples_for 'temporal table' do
  it { should_not have_public_backing }

  it { should have_temporal_backing }
  it { should have_history_backing }
  it { should have_history_extra_columns }
  it { should have_public_interface }

  it { should have_columns(columns) }
  it { should have_temporal_columns(columns) }
  it { should have_history_columns(columns) }
end

shared_examples_for 'plain table' do
  it { should have_public_backing }

  it { should_not have_temporal_backing }
  it { should_not have_history_backing }
  it { should_not have_public_interface }

  it { should have_columns(columns) }
end

describe ChronoModel::Adapter do
  include ChronoTest::Helpers::Adapter

  it { adapter.should be_a_kind_of(ChronoModel::Adapter) }

  let(:table) { 'test_table' }
  subject { table }

  columns do
    native = [
      ['test', 'character varying(255)'],
      ['foo',  'integer'],
      ['bar',  'double precision'],
      ['baz',  'text']
    ]

    def native.to_proc
      proc {|t|
        t.string  :test
        t.integer :foo
        t.float   :bar
        t.text    :baz
      }
    end

    native
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
    let(:table)   { 'test_table' }
    let(:renamed) { 'foo_table'  }
    subject { renamed }

    context ':temporal => true' do
      before :all do
        adapter.create_table table, :temporal => true, &columns

        adapter.rename_table table, renamed
      end
      after(:all) { adapter.drop_table(renamed) }

      it_should_behave_like 'temporal table'
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
        adapter.change_table subject, :temporal => false
      end

      it_should_behave_like 'plain table'
    end

    with_plain_table do
      before :all do
        adapter.change_table subject, :temporal => true
      end

      it_should_behave_like 'temporal table'
    end
  end

  describe '.drop_table' do
    before :all do
      adapter.create_table table, :temporal => true, &columns

      adapter.drop_table subject
    end

    it { should_not have_public_backing }
    it { should_not have_temporal_backing }
    it { should_not have_history_backing }
    it { should_not have_public_interface }
  end

  describe '.add_index' do
    with_temporal_table do
      before :all do
        adapter.add_index subject, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index subject, [:test],      :name => 'test_index'
      end

      it { should have_temporal_index 'foobar_index', %w( foo bar ) }
      it { should have_history_index  'foobar_index', %w( foo bar ) }
      it { should have_temporal_index 'test_index',   %w( test ) }
      it { should have_history_index  'test_index',   %w( test ) }

      it { should_not have_index 'foobar_index', %w( foo bar ) }
      it { should_not have_index 'test_index',   %w( test ) }
    end

    with_plain_table do
      before :all do
        adapter.add_index subject, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index subject, [:test],      :name => 'test_index'
      end

      it { should_not have_temporal_index 'foobar_index', %w( foo bar ) }
      it { should_not have_history_index  'foobar_index', %w( foo bar ) }
      it { should_not have_temporal_index 'test_index',   %w( test ) }
      it { should_not have_history_index  'test_index',   %w( test ) }

      it { should have_index 'foobar_index', %w( foo bar ) }
      it { should have_index 'test_index',   %w( test ) }
    end
  end

  describe '.remove_index' do
    with_temporal_table do
      before :all do
        adapter.add_index subject, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index subject, [:test],      :name => 'test_index'

        adapter.remove_index subject, :name => 'test_index'
      end

      it { should_not have_temporal_index 'test_index', %w( test ) }
      it { should_not have_history_index  'test_index', %w( test ) }
      it { should_not have_index          'test_index', %w( test ) }
    end

    with_plain_table do
      before :all do
        adapter.add_index subject, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index subject, [:test],      :name => 'test_index'

        adapter.remove_index subject, :name => 'test_index'
      end

      it { should_not have_temporal_index 'test_index', %w( test ) }
      it { should_not have_history_index  'test_index', %w( test ) }
      it { should_not have_index          'test_index', %w( test ) }
    end
  end

  describe '.add_column' do
    let(:extra_columns) { [['foobarbaz', 'integer']] }

    with_temporal_table do
      before :all do
        adapter.add_column subject, :foobarbaz, :integer
      end

      it { should have_columns(extra_columns) }
      it { should have_temporal_columns(extra_columns) }
      it { should have_history_columns(extra_columns) }
    end

    with_plain_table do
      before :all do
        adapter.add_column subject, :foobarbaz, :integer
      end

      it { should have_columns(extra_columns) }
    end
  end

  describe '.remove_column' do
    let(:resulting_columns) { columns.reject {|c,_| c == 'foo'} }

    with_temporal_table do
      before :all do
        adapter.remove_column subject, :foo
      end

      it { should have_columns(resulting_columns) }
      it { should have_temporal_columns(resulting_columns) }
      it { should have_history_columns(resulting_columns) }

      it { should_not have_columns([['foo', 'integer']]) }
      it { should_not have_temporal_columns([['foo', 'integer']]) }
      it { should_not have_history_columns([['foo', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.remove_column subject, :foo
      end

      it { should have_columns(resulting_columns) }
      it { should_not have_columns([['foo', 'integer']]) }
    end
  end

  describe '.rename_column' do
    with_temporal_table do
      before :all do
        adapter.rename_column subject, :foo, :taratapiatapioca
      end

      it { should_not have_columns([['foo', 'integer']]) }
      it { should_not have_temporal_columns([['foo', 'integer']]) }
      it { should_not have_history_columns([['foo', 'integer']]) }

      it { should have_columns([['taratapiatapioca', 'integer']]) }
      it { should have_temporal_columns([['taratapiatapioca', 'integer']]) }
      it { should have_history_columns([['taratapiatapioca', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.rename_column subject, :foo, :taratapiatapioca
      end

      it { should_not have_columns([['foo', 'integer']]) }
      it { should have_columns([['taratapiatapioca', 'integer']]) }
    end
  end

  describe '.change_column' do
    with_temporal_table do
      before :all do
        adapter.change_column subject, :foo, :float
      end

      it { should_not have_columns([['foo', 'integer']]) }
      it { should_not have_temporal_columns([['foo', 'integer']]) }
      it { should_not have_history_columns([['foo', 'integer']]) }

      it { should have_columns([['foo', 'double precision']]) }
      it { should have_temporal_columns([['foo', 'double precision']]) }
      it { should have_history_columns([['foo', 'double precision']]) }
    end

    with_plain_table do
      before(:all) do
        adapter.change_column subject, :foo, :float
      end

      it { should_not have_columns([['foo', 'integer']]) }
      it { should have_columns([['foo', 'double precision']]) }
    end
  end

  describe '.remove_column' do
    with_temporal_table do
      before :all do
        adapter.remove_column subject, :foo
      end

      it { should_not have_columns([['foo', 'integer']]) }
      it { should_not have_temporal_columns([['foo', 'integer']]) }
      it { should_not have_history_columns([['foo', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.remove_column subject, :foo
      end

      it { should_not have_columns([['foo', 'integer']]) }
    end
  end

end
