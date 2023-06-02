require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '#timeline' do
    split = ->(ts) { ts.map! { |t| [t.to_i, t.usec] } }

    timestamps_from = lambda { |*records|
      records.map(&:history).flatten!.inject([]) { |ret, rec|
        ret.push [rec.valid_from.to_i, rec.valid_from.usec] if rec.try(:valid_from)
        ret.push [rec.valid_to  .to_i, rec.valid_to  .usec] if rec.try(:valid_to)
        ret
      }.sort.uniq
    }

    describe 'on records having an :has_many relationship' do
      describe 'by default returns timestamps of the record only' do
        subject { split.call($t.foo.timeline) }

        it { expect(subject.size).to eq $t.foo.ts.size }
        it { is_expected.to eq timestamps_from.call($t.foo) }
      end

      describe 'when asked, returns timestamps including the related objects' do
        subject { split.call($t.foo.timeline(with: :bars)) }

        it { expect(subject.size).to eq($t.foo.ts.size + $t.bar.ts.size) }
        it { is_expected.to eq(timestamps_from.call($t.foo, *$t.foo.bars)) }
      end
    end

    describe 'on records using has_timeline :with' do
      subject { split.call($t.bar.timeline) }

      describe 'returns timestamps of the record and its associations' do
        let!(:expected) do
          creat = $t.bar.history.first.valid_from
          c_sec, c_usec = creat.to_i, creat.usec

          timestamps_from.call($t.foo, $t.bar).reject { |sec, usec|
            sec < c_sec || (sec == c_sec && usec < c_usec)
          }
        end

        it { expect(subject.size).to eq expected.size }
        it { is_expected.to eq expected }
      end
    end

    describe 'on non-temporal records using has_timeline :with' do
      subject { split.call($t.baz.timeline) }

      describe 'returns timestamps of its temporal associations' do
        it { expect(subject.size).to eq $t.bar.ts.size }
        it { is_expected.to eq timestamps_from.call($t.bar) }
      end
    end
  end
end
