require 'spec_helper'

describe ChronoModel::Adapter do
  let(:adapter) { ChronoTest::AR.connection }

  subject { adapter }

  it { should be_a_kind_of(ChronoModel::Adapter) }

  describe 'create_table' do
    let(:temporal_table) { 'temporal_table' }
    let(:plain_table)    { 'plain_table'    }

    context 'given the :temporal option' do
      subject { temporal_table }

      it 'should succeed' do
        lambda {
          adapter.create_table subject, :temporal => true do |t|
            t.string :test
          end
        }.should_not raise_error
      end

      it { should_not have_public_backing }

      it { should have_temporal_backing }
      it { should have_history_backing }
      it { should have_public_interface }
    end

    context 'without the :temporal option' do
      subject { plain_table }

      it 'should suceed' do
        lambda {
          adapter.create_table subject do |t|
            t.string :test
          end
        }.should_not raise_error
      end

      it { should have_public_backing }

      it { should_not have_temporal_backing }
      it { should_not have_history_backing }
      it { should_not have_public_interface }
    end

  end
end
