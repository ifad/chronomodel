# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '.as_of' do
    it { expect(Foo.as_of(1.month.ago)).to eq [] }

    it { expect(Foo.as_of($t.foos[0].ts[0])).to eq [$t.foo, $t.foos[0]] }
    it { expect(Foo.as_of($t.foos[1].ts[0])).to eq [$t.foo, $t.foos[0], $t.foos[1]] }
    it { expect(Foo.as_of(Time.now)).to eq [$t.foo, $t.foos[0], $t.foos[1]] }

    it { expect(Bar.as_of($t.foos[1].ts[0])).to eq [$t.bar] }

    it { expect(Bar.as_of($t.bars[0].ts[0])).to eq [$t.bar, $t.bars[0]] }
    it { expect(Bar.as_of($t.bars[1].ts[0])).to eq [$t.bar, $t.bars[0], $t.bars[1]] }
    it { expect(Bar.as_of(Time.now)).to eq [$t.bar, $t.bars[0], $t.bars[1]] }

    it { expect(Foo.as_of($t.foos[0].ts[0]).first).to be_a(Foo) }
    it { expect(Bar.as_of($t.foos[0].ts[0]).first).to be_a(Bar) }

    context 'with associations' do
      let(:id) { $t.foos[0].id }

      it { expect(Foo.as_of($t.foos[0].ts[0]).find(id).bars).to eq [] }
      it { expect(Foo.as_of($t.foos[1].ts[0]).find(id).bars).to eq [] }
      it { expect(Foo.as_of($t.bars[0].ts[0]).find(id).bars).to eq [$t.bars[0]] }
      it { expect(Foo.as_of($t.bars[1].ts[0]).find(id).bars).to eq [$t.bars[0]] }
      it { expect(Foo.as_of(Time.now).find(id).bars).to eq [$t.bars[0]] }

      it { expect(Foo.as_of($t.bars[0].ts[0]).find(id).bars.first).to be_a(Bar) }
    end

    context 'with association at a different timestamp' do
      let(:id) { $t.foos[1].id }

      it { expect { Foo.as_of($t.foos[0].ts[0]).find(id) }.to raise_error(ActiveRecord::RecordNotFound) }
      it { expect { Foo.as_of($t.foos[1].ts[0]).find(id) }.not_to raise_error }

      it { expect(Foo.as_of($t.bars[0].ts[0]).find(id).bars).to eq [] }
      it { expect(Foo.as_of($t.bars[1].ts[0]).find(id).bars).to eq [$t.bars[1]] }
      it { expect(Foo.as_of(Time.now).find(id).bars).to eq [$t.bars[1]] }
    end
  end

  describe '#as_of' do
    describe 'accepts a Time instance' do
      it { expect($t.foo.as_of(Time.now).name).to eq 'new foo' }
      it { expect($t.bar.as_of(Time.now).name).to eq 'new bar' }
    end

    describe 'ignores time zones' do
      it { expect($t.foo.as_of(Time.now.in_time_zone('America/Havana')).name).to eq 'new foo' }
      it { expect($t.bar.as_of(Time.now.in_time_zone('America/Havana')).name).to eq 'new bar' }
    end

    describe 'returns records as they were before' do
      it { expect($t.foo.as_of($t.foo.ts[0]).name).to eq 'foo' }
      it { expect($t.foo.as_of($t.foo.ts[1]).name).to eq 'foo bar' }
      it { expect($t.foo.as_of($t.foo.ts[2]).name).to eq 'new foo' }

      it { expect($t.bar.as_of($t.bar.ts[0]).name).to eq 'bar' }
      it { expect($t.bar.as_of($t.bar.ts[1]).name).to eq 'foo bar' }
      it { expect($t.bar.as_of($t.bar.ts[2]).name).to eq 'bar bar' }
      it { expect($t.bar.as_of($t.bar.ts[3]).name).to eq 'new bar' }
    end

    describe 'takes care of associated records' do
      it { expect($t.foo.as_of($t.foo.ts[0]).bars).to eq [] }
      it { expect($t.foo.as_of($t.foo.ts[1]).bars).to eq [] }
      it { expect($t.foo.as_of($t.foo.ts[2]).bars).to eq [$t.bar] }

      it { expect($t.foo.as_of($t.foo.ts[2]).bars.first.name).to eq 'foo bar' }

      it { expect($t.foo.as_of($t.bar.ts[0]).bars).to eq [$t.bar] }
      it { expect($t.foo.as_of($t.bar.ts[1]).bars).to eq [$t.bar] }
      it { expect($t.foo.as_of($t.bar.ts[2]).bars).to eq [$t.bar] }
      it { expect($t.foo.as_of($t.bar.ts[3]).bars).to eq [$t.bar] }

      it { expect($t.foo.as_of($t.bar.ts[0]).bars.first.name).to eq 'bar' }
      it { expect($t.foo.as_of($t.bar.ts[1]).bars.first.name).to eq 'foo bar' }
      it { expect($t.foo.as_of($t.bar.ts[2]).bars.first.name).to eq 'bar bar' }
      it { expect($t.foo.as_of($t.bar.ts[3]).bars.first.name).to eq 'new bar' }

      it { expect($t.bar.as_of($t.bar.ts[0]).foo).to eq $t.foo }
      it { expect($t.bar.as_of($t.bar.ts[1]).foo).to eq $t.foo }
      it { expect($t.bar.as_of($t.bar.ts[2]).foo).to eq $t.foo }
      it { expect($t.bar.as_of($t.bar.ts[3]).foo).to eq $t.foo }

      it { expect($t.bar.as_of($t.bar.ts[0]).foo.name).to eq 'foo bar' }
      it { expect($t.bar.as_of($t.bar.ts[1]).foo.name).to eq 'foo bar' }
      it { expect($t.bar.as_of($t.bar.ts[2]).foo.name).to eq 'new foo' }
      it { expect($t.bar.as_of($t.bar.ts[3]).foo.name).to eq 'new foo' }
    end

    describe 'supports historical queries with includes()' do
      it { expect(Foo.as_of($t.foo.ts[0]).includes(:bars).first.bars).to eq [] }
      it { expect(Foo.as_of($t.foo.ts[1]).includes(:bars).first.bars).to eq [] }
      it { expect(Foo.as_of($t.foo.ts[2]).includes(:bars).first.bars).to eq [$t.bar] }

      it { expect(Foo.as_of($t.foo.ts[0]).includes(:goo).first).to eq $t.foo }

      it { expect(Foo.as_of($t.bar.ts[0]).includes(:bars).first.bars.first.name).to eq 'bar' }
      it { expect(Foo.as_of($t.bar.ts[1]).includes(:bars).first.bars.first.name).to eq 'foo bar' }
      it { expect(Foo.as_of($t.bar.ts[2]).includes(:bars).first.bars.first.name).to eq 'bar bar' }
      it { expect(Foo.as_of($t.bar.ts[3]).includes(:bars).first.bars.first.name).to eq 'new bar' }

      it { expect(Foo.as_of($t.foo.ts[0]).includes(bars: :sub_bars).first.bars).to eq [] }
      it { expect(Foo.as_of($t.foo.ts[1]).includes(bars: :sub_bars).first.bars).to eq [] }
      it { expect(Foo.as_of($t.foo.ts[2]).includes(bars: :sub_bars).first.bars).to eq [$t.bar] }

      it { expect(Foo.as_of($t.bar.ts[0]).includes(bars: :sub_bars).first.bars.first.name).to eq 'bar' }
      it { expect(Foo.as_of($t.bar.ts[1]).includes(bars: :sub_bars).first.bars.first.name).to eq 'foo bar' }
      it { expect(Foo.as_of($t.bar.ts[2]).includes(bars: :sub_bars).first.bars.first.name).to eq 'bar bar' }
      it { expect(Foo.as_of($t.bar.ts[3]).includes(bars: :sub_bars).first.bars.first.name).to eq 'new bar' }

      it { expect(Bar.as_of($t.bar.ts[0]).includes(:foo).first.foo).to eq $t.foo }
      it { expect(Bar.as_of($t.bar.ts[1]).includes(:foo).first.foo).to eq $t.foo }
      it { expect(Bar.as_of($t.bar.ts[2]).includes(:foo).first.foo).to eq $t.foo }
      it { expect(Bar.as_of($t.bar.ts[3]).includes(:foo).first.foo).to eq $t.foo }

      it { expect(Bar.as_of($t.bar.ts[0]).includes(:foo).first.foo.name).to eq 'foo bar' }
      it { expect(Bar.as_of($t.bar.ts[1]).includes(:foo).first.foo.name).to eq 'foo bar' }
      it { expect(Bar.as_of($t.bar.ts[2]).includes(:foo).first.foo.name).to eq 'new foo' }
      it { expect(Bar.as_of($t.bar.ts[3]).includes(:foo).first.foo.name).to eq 'new foo' }

      it { expect(Bar.as_of($t.bar.ts[0]).includes(foo: :sub_bars).first.foo).to eq $t.foo }
      it { expect(Bar.as_of($t.bar.ts[1]).includes(foo: :sub_bars).first.foo).to eq $t.foo }
      it { expect(Bar.as_of($t.bar.ts[2]).includes(foo: :sub_bars).first.foo).to eq $t.foo }
      it { expect(Bar.as_of($t.bar.ts[3]).includes(foo: :sub_bars).first.foo).to eq $t.foo }

      it { expect(Bar.as_of($t.bar.ts[0]).includes(foo: :sub_bars).first.foo.name).to eq 'foo bar' }
      it { expect(Bar.as_of($t.bar.ts[1]).includes(foo: :sub_bars).first.foo.name).to eq 'foo bar' }
      it { expect(Bar.as_of($t.bar.ts[2]).includes(foo: :sub_bars).first.foo.name).to eq 'new foo' }
      it { expect(Bar.as_of($t.bar.ts[3]).includes(foo: :sub_bars).first.foo.name).to eq 'new foo' }

      it { expect(Foo.as_of($t.foo.ts[0]).includes(:bars, :sub_bars).first.sub_bars.count).to eq 0 }
      it { expect(Foo.as_of($t.foo.ts[1]).includes(:bars, :sub_bars).first.sub_bars.count).to eq 0 }
      it { expect(Foo.as_of($t.foo.ts[2]).includes(:bars, :sub_bars).first.sub_bars.count).to eq 1 }

      it { expect(Foo.as_of($t.foo.ts[0]).includes(:bars, :sub_bars).first.sub_bars.first).to be_nil }
      it { expect(Foo.as_of($t.foo.ts[1]).includes(:bars, :sub_bars).first.sub_bars.first).to be_nil }

      it { expect(Foo.as_of($t.bar.ts[0]).includes(:sub_bars).first.bars.first.sub_bars.first).to be_nil }
      it { expect(Foo.as_of($t.subbar.ts[0]).includes(:sub_bars).first.bars.first.sub_bars.first.name).to eq 'sub-bar' }

      it { expect(Foo.as_of($t.subbar.ts[0]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'sub-bar' }
      it { expect(Foo.as_of($t.subbar.ts[1]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'bar sub-bar' }
      it { expect(Foo.as_of($t.subbar.ts[2]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'sub-bar sub-bar' }
      it { expect(Foo.as_of($t.subbar.ts[3]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'new sub-bar' }

      it { expect(Foo.as_of(Time.now).includes(:bars, :sub_bars, :sub_sub_bars).first.sub_sub_bars.compact.size).to eq 1 }

      it { expect(Foo.as_of(Time.now).includes(:active_sub_bars).first.name).to eq 'new foo' }
    end

    it 'does not raise RecordNotFound when no history records are found' do
      expect { $t.foo.as_of(5.minutes.ago) }.not_to raise_error

      expect($t.foo.as_of(5.minutes.ago)).to be_nil
    end

    it 'raises ActiveRecord::RecordNotFound in the bang variant' do
      expect { $t.foo.as_of!(5.minutes.ago) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    describe 'proxies from non-temporal models to temporal ones' do
      it { expect($t.baz.as_of($t.bar.ts[0]).name).to eq 'baz' }
      it { expect($t.baz.as_of($t.bar.ts[1]).name).to eq 'baz' }
      it { expect($t.baz.as_of($t.bar.ts[2]).name).to eq 'baz' }
      it { expect($t.baz.as_of($t.bar.ts[3]).name).to eq 'baz' }

      it { expect($t.baz.as_of($t.bar.ts[0]).bar.name).to eq 'bar' }
      it { expect($t.baz.as_of($t.bar.ts[1]).bar.name).to eq 'foo bar' }
      it { expect($t.baz.as_of($t.bar.ts[2]).bar.name).to eq 'bar bar' }
      it { expect($t.baz.as_of($t.bar.ts[3]).bar.name).to eq 'new bar' }

      it { expect($t.baz.as_of($t.bar.ts[0]).bar.foo.name).to eq 'foo bar' }
      it { expect($t.baz.as_of($t.bar.ts[1]).bar.foo.name).to eq 'foo bar' }
      it { expect($t.baz.as_of($t.bar.ts[2]).bar.foo.name).to eq 'new foo' }
      it { expect($t.baz.as_of($t.bar.ts[3]).bar.foo.name).to eq 'new foo' }
    end

    describe '#load' do
      it 'returns a relation' do
        expect(Foo.as_of(Time.now).load).to be_an(ActiveRecord::Relation)
      end
    end

    describe 'includes with joins regression' do
      # This tests the fix for the issue where includes + joins didn't work correctly
      # with temporal queries due to eager_loading? returning true and skipping includes_values
      context 'with includes and joins combined' do
        let(:historical_time) { $t.bar.ts[0] }  # Use a timestamp when data existed differently

        it 'works with joins alone' do
          # This should work - joins uses build_arel temporal processing
          result = Bar.as_of(historical_time).joins(:foo)
          expect(result).not_to be_empty
        end

        it 'works with includes alone' do
          # This should work - includes uses preload_associations temporal processing
          result = Bar.as_of(historical_time).includes(:foo)
          expect(result).not_to be_empty
        end

        it 'works with includes and joins together' do
          # This is the regression test - includes + joins should work together
          # Before the fix, this would skip includes_values when eager_loading? was true
          result = Bar.as_of(historical_time).includes(:foo).joins(:foo)
          expect(result).not_to be_empty
          
          # Verify that the temporal data is correctly loaded for the association
          first_bar = result.first
          expect(first_bar.foo).not_to be_nil
          # The foo association should have the temporal data from historical_time
          expect(first_bar.foo.as_of_time).to eq(historical_time)
        end
      end
    end
  end
end
