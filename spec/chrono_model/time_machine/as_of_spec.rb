require 'spec_helper'
require 'support/helpers'
require 'spec/chrono_model/time_machine/schema'

describe ChronoModel::TimeMachine do
  include ChronoTest::Helpers::TimeMachine

  describe '.as_of' do
    it { expect(Foo.as_of(1.month.ago)).to eq [] }

    it { expect(Foo.as_of($t.foos[0].ts[0])).to eq [$t.foo, $t.foos[0]] }
    it { expect(Foo.as_of($t.foos[1].ts[0])).to eq [$t.foo, $t.foos[0], $t.foos[1]] }
    it { expect(Foo.as_of(Time.now     )).to eq [$t.foo, $t.foos[0], $t.foos[1]] }

    it { expect(Bar.as_of($t.foos[1].ts[0])).to eq [$t.bar] }

    it { expect(Bar.as_of($t.bars[0].ts[0])).to eq [$t.bar, $t.bars[0]] }
    it { expect(Bar.as_of($t.bars[1].ts[0])).to eq [$t.bar, $t.bars[0], $t.bars[1]] }
    it { expect(Bar.as_of(Time.now     )).to eq [$t.bar, $t.bars[0], $t.bars[1]] }


    # Associations
    context do
      subject { $t.foos[0].id }

      it { expect(Foo.as_of($t.foos[0].ts[0]).find(subject).bars).to eq [] }
      it { expect(Foo.as_of($t.foos[1].ts[0]).find(subject).bars).to eq [] }
      it { expect(Foo.as_of($t.bars[0].ts[0]).find(subject).bars).to eq [$t.bars[0]] }
      it { expect(Foo.as_of($t.bars[1].ts[0]).find(subject).bars).to eq [$t.bars[0]] }
      it { expect(Foo.as_of(Time.now        ).find(subject).bars).to eq [$t.bars[0]] }
    end


    # find() on history relations
    context do
      subject { $t.foos[1].id }

      it { expect { Foo.as_of($t.foos[0].ts[0]).find(subject) }.to raise_error(ActiveRecord::RecordNotFound) }
      it { expect { Foo.as_of($t.foos[1].ts[0]).find(subject) }.to_not raise_error }

      it { expect(Foo.as_of($t.bars[0].ts[0]).find(subject).bars).to eq [] }
      it { expect(Foo.as_of($t.bars[1].ts[0]).find(subject).bars).to eq [$t.bars[1]] }
      it { expect(Foo.as_of(Time.now        ).find(subject).bars).to eq [$t.bars[1]] }
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

      it { expect(Foo.as_of($t.foo.ts[0]).includes(:bars, :sub_bars).first.sub_bars.first).to be nil }
      it { expect(Foo.as_of($t.foo.ts[1]).includes(:bars, :sub_bars).first.sub_bars.first).to be nil }

      it { expect(Foo.as_of($t.subbar.ts[0]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'sub-bar' }
      it { expect(Foo.as_of($t.subbar.ts[1]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'bar sub-bar' }
      it { expect(Foo.as_of($t.subbar.ts[2]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'sub-bar sub-bar' }
      it { expect(Foo.as_of($t.subbar.ts[3]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'new sub-bar' }
    end


    it 'does not raise RecordNotFound when no history records are found' do
      expect { $t.foo.as_of(1.minute.ago) }.to_not raise_error

      expect($t.foo.as_of(1.minute.ago)).to be(nil)
    end


    it 'raises ActiveRecord::RecordNotFound in the bang variant' do
      expect { $t.foo.as_of!(1.minute.ago) }.to raise_error(ActiveRecord::RecordNotFound)
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
  end
end
