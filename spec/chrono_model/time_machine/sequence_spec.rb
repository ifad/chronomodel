require 'spec_helper'
require 'support/time_machine/structure'

describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '#pred' do
    context 'on the first history entry' do
      subject { $t.foo.history.first.pred }
      it { is_expected.to be(nil) }
    end

    context 'on the second history entry' do
      subject { $t.foo.history.second.pred }
      it { is_expected.to eq $t.foo.history.first }
    end

    context 'on the last history entry' do
      subject { $t.foo.history.last.pred }
      it { is_expected.to eq $t.foo.history[$t.foo.history.size - 2] }
    end

    context 'on records having history' do
      subject { $t.bar.pred }
      it { expect(subject.name).to eq 'bar bar' }
    end

    context 'when there is enough history' do
      subject { $t.bar.pred.pred.pred.pred }
      it { expect(subject.name).to eq 'bar' }
    end

    context 'when no history is recorded' do
      let(:record) { Bar.create!(:name => 'quuuux') }

      subject { record.pred }

      it { is_expected.to be(nil) }

      after { record.destroy.history.delete_all }
    end
  end

  describe '#succ' do
    context 'on the first history entry' do
      subject { $t.foo.history.first.succ }

      it { is_expected.to eq $t.foo.history.second }
    end

    context 'on the second history entry' do
      subject { $t.foo.history.second.succ }

      it { is_expected.to eq $t.foo.history.third }
    end

    context 'on the last history entry' do
      subject { $t.foo.history.last.succ }

      it { is_expected.to be(nil) }
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
