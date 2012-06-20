require 'spec_helper'

shared_examples_for 'temporal table' do
  it { should_not have_public_backing }

  it { should have_temporal_backing }
  it { should have_history_backing }
  it { should have_public_interface }
end

shared_examples_for 'plain table' do
  it { should have_public_backing }

  it { should_not have_temporal_backing }
  it { should_not have_history_backing }
  it { should_not have_public_interface }
end

describe ChronoModel::Adapter do
  let(:adapter) { ChronoTest::AR.connection }

  subject { adapter }

  it { should be_a_kind_of(ChronoModel::Adapter) }

  columns = proc {|t|
    t.string  :test
    t.integer :foo
    t.float   :bar
    t.text    :baz
  }

  describe '.create_table' do
    subject { 'test_table' }

    context ':temporal => true' do
      before(:all) { adapter.create_table subject, :temporal => true, &columns }
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'temporal table'
    end

    context ':temporal => false' do
      before(:all) { adapter.create_table subject, &columns }
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
        adapter.create_table original, :temporal => true, &columns
        adapter.rename_table original, renamed
      end
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'temporal table'
    end

    context ':temporal => false' do
      before :all do
        adapter.create_table original, &columns
        adapter.rename_table original, renamed
      end
      after(:all) { adapter.drop_table subject }

      it_should_behave_like 'plain table'
    end
  end

end
