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
  it { should have_history_columns }
  it { should have_public_interface }

  it { should have_columns(columns) }
end

shared_examples_for 'plain table' do
  it { should have_public_backing }

  it { should_not have_temporal_backing }
  it { should_not have_history_backing }
  it { should_not have_public_interface }

  it { should have_columns(columns) }
end

describe ChronoModel::Adapter do
  let(:adapter) { ChronoTest::AR.connection }

  subject { adapter }

  it { should be_a_kind_of(ChronoModel::Adapter) }


  describe '.create_table' do
    subject { 'test_table' }

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
    subject { 'test_table' }

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
    subject { 'test_table' }

    before :all do
      adapter.create_table subject, :temporal => true, &table
      adapter.drop_table subject
    end

    it { should_not have_public_backing }
    it { should_not have_temporal_backing }
    it { should_not have_history_backing }
    it { should_not have_public_interface }
  end

end
