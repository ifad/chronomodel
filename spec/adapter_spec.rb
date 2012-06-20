require 'spec_helper'

columns = [
  ['test', 'character varying(255)'],
  ['foo',  'integer'],
  ['bar',  'double precision'],
  ['baz',  'text']
]

table = proc {|t|
  t.string  :test
  t.integer :foo
  t.float   :bar
  t.text    :baz
}

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
  let(:adapter) { ChronoTest.connection }
  it { adapter.should be_a_kind_of(ChronoModel::Adapter) }

  subject { 'test_table' }

  describe '.create_table' do
    context ':temporal => true' do
      before(:all) { adapter.create_table subject, :temporal => true, &table }
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'temporal table'
    end

    context ':temporal => false' do
      before(:all) { adapter.create_table subject, &table }
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'plain table'
    end
  end

  describe '.rename_table' do
    let(:original) { 'test_table' }
    let(:renamed ) { 'foo_table'  }

    subject { renamed }

    context ':temporal => true' do
      before :all do
        adapter.create_table original, :temporal => true, &table
        adapter.rename_table original, renamed
      end
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'temporal table'
    end

    context ':temporal => false' do
      before :all do
        adapter.create_table original, &table
        adapter.rename_table original, renamed
      end
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'plain table'
    end
  end

  describe '.change_table' do
    context ':temporal => true on a non-temporal table' do
      before :all do
        adapter.create_table subject, :temporal => false, &table
        adapter.change_table subject, :temporal => true
      end
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'temporal table'
    end

    context ':temporal => false on a temporal table' do
      before :all do
        adapter.create_table subject, :temporal => true, &table
        adapter.change_table subject, :temporal => false
      end
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'plain table'
    end
  end

  describe '.drop_table' do
    before :all do
      adapter.create_table subject, :temporal => true, &table
      adapter.drop_table subject
    end

    it { should_not have_public_backing }
    it { should_not have_temporal_backing }
    it { should_not have_history_backing }
    it { should_not have_public_interface }
  end

  describe '.add_index' do
    context ':temporal => true' do
      before :all do
        adapter.create_table subject, :temporal => true, &table

        adapter.add_index subject, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index subject, [:test],      :name => 'test_index'
      end
      after(:all) { adapter.drop_table subject }

      it { should have_temporal_index 'foobar_index', %w( foo bar ) }
      it { should have_history_index  'foobar_index', %w( foo bar ) }
      it { should have_temporal_index 'test_index',   %w( test ) }
      it { should have_history_index  'test_index',   %w( test ) }

      it { should_not have_index 'foobar_index', %w( foo bar ) }
      it { should_not have_index 'test_index',   %w( test ) }
    end

    context ':temporal => false' do
      before :all do
        adapter.create_table subject, :temporal => false, &table

        adapter.add_index subject, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index subject, [:test],      :name => 'test_index'
      end
      after(:all) { adapter.drop_table subject }

      it { should_not have_temporal_index 'foobar_index', %w( foo bar ) }
      it { should_not have_history_index  'foobar_index', %w( foo bar ) }
      it { should_not have_temporal_index 'test_index',   %w( test ) }
      it { should_not have_history_index  'test_index',   %w( test ) }

      it { should have_index 'foobar_index', %w( foo bar ) }
      it { should have_index 'test_index',   %w( test ) }
    end
  end

  describe '.remove_index' do
    context ':temporal => true' do
      before :all do
        adapter.create_table subject, :temporal => true, &table
        adapter.add_index subject, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index subject, [:test],      :name => 'test_index'

        adapter.remove_index subject, :name => 'test_index'
      end
      after(:all) { adapter.drop_table subject }

      it { should_not have_temporal_index 'test_index', %w( test ) }
      it { should_not have_history_index  'test_index', %w( test ) }
      it { should_not have_index          'test_index', %w( test ) }
    end

    context ':temporal => false' do
      before :all do
        adapter.create_table subject, :temporal => false, &table
        adapter.add_index subject, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index subject, [:test],      :name => 'test_index'

        adapter.remove_index subject, :name => 'test_index'
      end
      after(:all) { adapter.drop_table subject }

      it { should_not have_temporal_index 'test_index', %w( test ) }
      it { should_not have_history_index  'test_index', %w( test ) }
      it { should_not have_index          'test_index', %w( test ) }
    end
  end

  describe '.add_column' do
    let(:extra_columns) { [['foobarbaz', 'integer']] }

    context ':temporal => true' do
      before :all do
        adapter.create_table subject, :temporal => true, &table

        adapter.add_column subject, :foobarbaz, :integer
      end
      after(:all) { adapter.drop_table subject }

      it { should have_columns(extra_columns) }
      it { should have_temporal_columns(extra_columns) }
      it { should have_history_columns(extra_columns) }
    end

    context ':temporal => false' do
      before :all do
        adapter.create_table subject, :temporal => false, &table

        adapter.add_column subject, :foobarbaz, :integer
      end
      after(:all) { adapter.drop_table subject }

      it { should have_columns(extra_columns) }
    end
  end

  describe '.remove_column' do
    let(:resulting_columns) { columns.reject {|c,_| c == 'foo'} }

    context ':temporal => true' do
      before :all do
        adapter.create_table subject, :temporal => true, &table

        adapter.remove_column subject, :foo
      end
      after(:all) { adapter.drop_table subject }

      it { should have_columns(resulting_columns) }
      it { should have_temporal_columns(resulting_columns) }
      it { should have_history_columns(resulting_columns) }

      it { should_not have_columns([['foo', 'integer']]) }
      it { should_not have_temporal_columns([['foo', 'integer']]) }
      it { should_not have_history_columns([['foo', 'integer']]) }
    end

    context ':temporal => false' do
      before :all do
        adapter.create_table subject, :temporal => false, &table

        adapter.remove_column subject, :foo
      end
      after(:all) { adapter.drop_table subject }

      it { should have_columns(resulting_columns) }
      it { should_not have_columns([['foo', 'integer']]) }
    end
  end


  describe '.rename_column' do
    context ':temporal => true' do
      before :all do
        adapter.create_table subject, :temporal => true, &table

        adapter.rename_column subject, :foo, :taratapiatapioca
      end
      after(:all) { adapter.drop_table subject }

      it { should_not have_columns([['foo', 'integer']]) }
      it { should_not have_temporal_columns([['foo', 'integer']]) }
      it { should_not have_history_columns([['foo', 'integer']]) }

      it { should have_columns([['taratapiatapioca', 'integer']]) }
      it { should have_temporal_columns([['taratapiatapioca', 'integer']]) }
      it { should have_history_columns([['taratapiatapioca', 'integer']]) }
    end

    context ':temporal => false' do
      before :all do
        adapter.create_table subject, :temporal => false, &table

        adapter.rename_column subject, :foo, :taratapiatapioca
      end
      after(:all) { adapter.drop_table subject }

      it { should_not have_columns([['foo', 'integer']]) }
      it { should have_columns([['taratapiatapioca', 'integer']]) }
    end
  end

end
