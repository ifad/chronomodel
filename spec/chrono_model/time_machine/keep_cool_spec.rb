# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe 'does not interfere with AR standard behaviour' do
    let(:all_foos) { [$t.foo] + $t.foos }
    let(:all_bars) { [$t.bar] + $t.bars }

    it { expect(Foo.count).to eq all_foos.size }
    it { expect(Bar.count).to eq all_bars.size }

    it { expect(Foo.includes(bars: :sub_bars)).to eq all_foos }
    it { expect(Foo.includes(:bars).preload(bars: :sub_bars)).to eq all_foos }
    it { expect(Foo.includes(:bars).preload(bars: :sub_bars).as_of(Time.now)).to eq all_foos }

    it { expect(Foo.includes(:bars).first.name).to eq 'new foo' }
    it { expect(Foo.includes(:bars).as_of($t.foo.ts[0]).first.name).to eq 'foo' }

    it { expect(Foo.joins(:bars).map(&:bars).flatten).to eq all_bars }
    it { expect(Foo.joins(:bars).first.bars.joins(:sub_bars).first.name).to eq 'new bar' }

    it { expect(Foo.joins(bars: :sub_bars).first.bars.joins(:sub_bars).first.sub_bars.first.name).to eq 'new sub-bar' }

    it { expect(Foo.first.bars.includes(:sub_bars)).to eq [$t.bar] }

    it { expect(Moo.first.boos).to eq(Boo.all) }
    it { expect(Moo.first.boos.as_of(Time.now)).to eq(Boo.all.as_of(Time.now)) }
  end
end
