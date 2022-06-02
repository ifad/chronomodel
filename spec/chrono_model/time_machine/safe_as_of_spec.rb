require 'spec_helper'
require 'support/time_machine/structure'

describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '.safe_as_of' do
    it { expect(Foo.safe_as_of($t.foos[0].ts[0])).to eq Foo.as_of($t.foos[0].ts[0]) }
    it { expect(Foo.safe_as_of(nil)).to eq Foo.all }

    it { expect(FooGoo.safe_as_of($t.goo_foos[0].ts[0]).first.foos).to eq $t.goo.as_of($t.goo_foos[0].ts[0]).foos }
    it { expect(FooGoo.safe_as_of(nil).first.foos).to eq $t.goo.foos }
  end
end
