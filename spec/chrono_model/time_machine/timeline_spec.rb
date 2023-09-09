# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '#timeline' do
    split = ->(ts) { ts.map! { |t| [t.to_i, t.usec] } }

    timestamps_from = lambda { |*records|
      records.map(&:history).flatten!.each_with_object([]) do |rec, ret|
        ret.push [rec.valid_from.to_i, rec.valid_from.usec] if rec.try(:valid_from)
        ret.push [rec.valid_to.to_i, rec.valid_to.usec] if rec.try(:valid_to)
      end.sort.uniq
    }

    context 'with records having an :has_many relationship' do
      context 'with default settings' do
        subject(:timeline) { split.call($t.foo.timeline) }

        it { expect(timeline.size).to eq $t.foo.ts.size }
        it { is_expected.to eq timestamps_from.call($t.foo) }
      end

      context 'when association is requested in options' do
        subject(:timeline) { split.call($t.foo.timeline(with: :bars)) }

        it { expect(timeline.size).to eq($t.foo.ts.size + $t.bar.ts.size) }
        it { is_expected.to eq(timestamps_from.call($t.foo, *$t.foo.bars)) }
      end
    end

    context 'with records using has_timeline :with' do
      subject(:timeline) { split.call($t.bar.timeline) }

      let!(:expected) do
        creat = $t.bar.history.first.valid_from
        c_sec = creat.to_i
        c_usec = creat.usec

        timestamps_from.call($t.foo, $t.bar).reject do |sec, usec|
          sec < c_sec || (sec == c_sec && usec < c_usec)
        end
      end

      it { expect(timeline.size).to eq expected.size }
      it { is_expected.to eq expected }
    end

    context 'with non-temporal records using has_timeline :with' do
      subject(:timeline) { split.call($t.baz.timeline) }

      it { expect(timeline.size).to eq $t.bar.ts.size }
      it { is_expected.to eq timestamps_from.call($t.bar) }
    end
  end
end
