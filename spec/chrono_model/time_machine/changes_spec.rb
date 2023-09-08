require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '#last_changes' do
    context 'on plain records' do
      context 'having history' do
        subject { $t.bar.last_changes }

        it { is_expected.to eq('name' => ['bar bar', 'new bar']) }
      end

      context 'without history' do
        subject { record.last_changes }

        let(:record) { Bar.create!(name: 'foreveralone') }

        after { record.destroy.history.delete_all } # UGLY

        it { is_expected.to be_nil }
      end
    end

    context 'on history records' do
      context 'at the beginning of the timeline' do
        subject { $t.bar.history.first.last_changes }

        it { is_expected.to be_nil }
      end

      context 'in the middle of the timeline' do
        subject { $t.bar.history.second.last_changes }

        it { is_expected.to eq('name' => ['bar', 'foo bar']) }
      end
    end
  end

  describe '#changes_against' do
    context 'can compare records against history' do
      it { expect($t.bar.changes_against($t.bar.history.first)).to eq('name' => ['bar', 'new bar']) }
      it { expect($t.bar.changes_against($t.bar.history.second)).to eq('name' => ['foo bar', 'new bar']) }
      it { expect($t.bar.changes_against($t.bar.history.third)).to eq('name' => ['bar bar', 'new bar']) }
      it { expect($t.bar.changes_against($t.bar.history.last)).to eq({}) }
    end

    context 'can compare history against history' do
      it { expect($t.bar.history.first.changes_against($t.bar.history.third)).to eq('name' => ['bar bar', 'bar']) }
      it { expect($t.bar.history.second.changes_against($t.bar.history.third)).to eq('name' => ['bar bar', 'foo bar']) }
      it { expect($t.bar.history.third.changes_against($t.bar.history.third)).to eq({}) }
    end
  end
end
