require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '#save' do
    subject { $t.bar.history.first }

    let(:another_historical_object) { $t.bar.history.second }

    it do
      with_revert do
        subject.name = 'modified bar history'
        subject.save
        subject.reload

        is_expected.to be_a(Bar::History)
        expect(another_historical_object.name).not_to eq 'modified bar history'
        expect(subject.name).to eq 'modified bar history'
      end
    end
  end

  describe '#save!' do
    subject { $t.bar.history.second }

    let(:first_historical_object) { $t.bar.history.first }

    it do
      with_revert do
        subject.name = 'another modified bar history'
        subject.save!
        subject.reload

        is_expected.to be_a(Bar::History)
        expect(first_historical_object.name).not_to eq 'another modified bar history'
        expect(subject.name).to eq 'another modified bar history'
      end
    end
  end

  describe '#update_columns' do
    subject { $t.bar.history.first }

    let(:another_historical_object) { $t.bar.history.second }

    it do
      with_revert do
        subject.update_columns name: 'another modified bar history'
        subject.reload

        is_expected.to be_a(Bar::History)
        expect(another_historical_object.name).not_to eq 'another modified bar history'
        expect(subject.name).to eq 'another modified bar history'
      end
    end
  end

  describe '#destroy' do
    describe 'on historical records' do
      subject { $t.foo.history.first.destroy }

      it { expect { subject }.to raise_error(ActiveRecord::ReadOnlyRecord) }
    end

    describe 'on current records' do
      rec = nil
      subject { rec.destroy }

      before(:all) do
        rec = ts_eval { Foo.create!(name: 'alive foo', fooity: 42) }
        ts_eval(rec) { update!(name: 'dying foo') }
      end

      after(:all) do
        rec.history.delete_all
      end


      it { expect { subject }.to_not raise_error }
      it { expect { rec.reload }.to raise_error(ActiveRecord::RecordNotFound) }

      describe 'does not delete its history' do
        subject { record.name }

        context do
          let(:record) { rec.as_of(rec.ts.first) }

          it { is_expected.to eq 'alive foo' }
        end

        context do
          let(:record) { rec.as_of(rec.ts.last) }

          it { is_expected.to eq 'dying foo' }
        end

        context do
          let(:record) { Foo.as_of(rec.ts.first).where(fooity: 42).first }

          it { is_expected.to eq 'alive foo' }
        end

        context do
          subject { Foo.history.where(fooity: 42).map(&:name) }

          it { is_expected.to eq ['alive foo', 'dying foo'] }
        end
      end
    end
  end
end
