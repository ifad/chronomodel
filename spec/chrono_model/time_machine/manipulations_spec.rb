# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '#save' do
    let(:historical_object) { $t.bar.history.first }
    let(:another_historical_object) { $t.bar.history.second }

    it do
      with_revert do
        historical_object.name = 'modified bar history'
        historical_object.save
        historical_object.reload

        expect(historical_object).to be_a(Bar::History)
        expect(another_historical_object.name).not_to eq 'modified bar history'
        expect(historical_object.name).to eq 'modified bar history'
      end
    end
  end

  describe '#save!' do
    let(:first_historical_object) { $t.bar.history.first }
    let(:second_historical_object) { $t.bar.history.second }

    it do
      with_revert do
        second_historical_object.name = 'another modified bar history'
        second_historical_object.save!
        second_historical_object.reload

        expect(second_historical_object).to be_a(Bar::History)
        expect(first_historical_object.name).not_to eq 'another modified bar history'
        expect(second_historical_object.name).to eq 'another modified bar history'
      end
    end
  end

  describe '#update_columns' do
    let(:historical_object) { $t.bar.history.first }
    let(:another_historical_object) { $t.bar.history.second }

    it do
      with_revert do
        historical_object.update_columns name: 'another modified bar history'
        historical_object.reload

        expect(historical_object).to be_a(Bar::History)
        expect(another_historical_object.name).not_to eq 'another modified bar history'
        expect(historical_object.name).to eq 'another modified bar history'
      end
    end
  end

  describe '#destroy' do
    describe 'on historical records' do
      subject(:destroy) { $t.foo.history.first.destroy }

      it { expect { destroy }.to raise_error(ActiveRecord::ReadOnlyRecord) }
    end

    describe 'on current records' do
      rec = nil
      subject(:destroy) { rec.destroy }

      before do
        rec = ts_eval { Foo.create!(name: 'alive foo', fooity: 42) }
        ts_eval(rec) { update!(name: 'dying foo') }
      end

      after do
        rec.history.delete_all
      end

      it { expect { destroy }.not_to raise_error }

      it 'raises an error when record is reloaded' do
        destroy

        expect { rec.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end

      describe 'does not delete its history' do
        subject { record.name }

        context 'with first timestamp' do
          let(:record) { rec.as_of(rec.ts.first) }

          it { is_expected.to eq 'alive foo' }
        end

        context 'with last timestamp' do
          let(:record) { rec.as_of(rec.ts.last) }

          it { is_expected.to eq 'dying foo' }
        end

        context 'when searching with as_of' do
          let(:record) { Foo.as_of(rec.ts.first).where(fooity: 42).first }

          it { is_expected.to eq 'alive foo' }
        end

        context 'when searching in history' do
          subject { Foo.history.where(fooity: 42).map(&:name) }

          it { is_expected.to eq ['alive foo', 'dying foo'] }
        end
      end
    end
  end
end
