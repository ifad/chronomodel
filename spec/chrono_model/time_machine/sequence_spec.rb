# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '#pred' do
    context 'with the first history entry' do
      subject { $t.foo.history.first.pred }

      it { is_expected.to be_nil }
    end

    context 'with the second history entry' do
      subject { $t.foo.history.second.pred }

      it { is_expected.to eq $t.foo.history.first }
    end

    context 'with the last history entry' do
      subject { $t.foo.history.last.pred }

      it { is_expected.to eq $t.foo.history[$t.foo.history.size - 2] }
    end

    context 'with current records without an associated timeline' do
      subject { $t.noo.pred }

      it { is_expected.to eq $t.noo.history.first }
    end

    context 'with records having history' do
      subject(:pred) { $t.bar.pred }

      it { expect(pred.name).to eq 'bar bar' }
    end

    context 'when there is enough history' do
      subject(:pred) { $t.bar.pred.pred.pred.pred }

      it { expect(pred.name).to eq 'bar' }
    end

    context 'when no history is recorded' do
      subject { record.pred }

      let(:record) { Bar.create!(name: 'quuuux') }

      after { record.destroy.history.delete_all }

      it { is_expected.to be_nil }
    end
  end

  describe '#succ' do
    context 'with the first history entry' do
      subject { $t.foo.history.first.succ }

      it { is_expected.to eq $t.foo.history.second }
    end

    context 'with the second history entry' do
      subject { $t.foo.history.second.succ }

      it { is_expected.to eq $t.foo.history.third }
    end

    context 'with the last history entry' do
      subject { $t.foo.history.last.succ }

      it { is_expected.to be_nil }
    end
  end

  describe '#next' do
    let(:record) { $t.foo.history.first }

    it 'is an alias of succ' do
      expect(record.method(:next).original_name).to eq(:succ)
    end
  end

  describe '#first' do
    subject { $t.foo.history.sample.first }

    it { is_expected.to eq $t.foo.history.first }
  end

  describe '#last' do
    subject { $t.foo.history.sample.last }

    it { is_expected.to eq $t.foo.history.last }
  end
end
