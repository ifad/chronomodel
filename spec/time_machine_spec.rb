require 'spec_helper'
require 'support/helpers'

describe ChronoModel::TimeMachine do
  include ChronoTest::Helpers::TimeMachine

  setup_schema!
  define_models!

  describe '.chrono_models' do
    subject { ChronoModel::TimeMachine.chrono_models }

    it { should == {'foos' => Foo, 'bars' => Bar} }
  end


  # Set up two associated records, with intertwined updates
  #
  let!(:foo) {
    foo = ts_eval { Foo.create! :name => 'foo', :fooity => 1 }
    ts_eval(foo) { update_attributes! :name => 'foo bar' }
  }

  let!(:bar) {
    bar = ts_eval { Bar.create! :name => 'bar', :foo => foo }
    ts_eval(bar) { update_attributes! :name => 'foo bar' }

    ts_eval(foo) { update_attributes! :name => 'new foo' }

    ts_eval(bar) { update_attributes! :name => 'bar bar' }
    ts_eval(bar) { update_attributes! :name => 'new bar' }
  }

  # Specs start here
  #
  describe '#as_of' do
    describe 'accepts a Time instance' do
      it { foo.as_of(Time.now).name.should == 'new foo' }
      it { bar.as_of(Time.now).name.should == 'new bar' }
    end

    describe 'ignores time zones' do
      it { foo.as_of(Time.now.in_time_zone('America/Havana')).name.should == 'new foo' }
      it { bar.as_of(Time.now.in_time_zone('America/Havana')).name.should == 'new bar' }
    end

    describe 'returns records as they were before' do
      it { foo.as_of(foo.ts[0]).name.should == 'foo' }
      it { foo.as_of(foo.ts[1]).name.should == 'foo bar' }
      it { foo.as_of(foo.ts[2]).name.should == 'new foo' }

      it { bar.as_of(bar.ts[0]).name.should == 'bar' }
      it { bar.as_of(bar.ts[1]).name.should == 'foo bar' }
      it { bar.as_of(bar.ts[2]).name.should == 'bar bar' }
      it { bar.as_of(bar.ts[3]).name.should == 'new bar' }
    end

    describe 'takes care of associated records' do
      it { foo.as_of(foo.ts[0]).bars.should == [] }
      it { foo.as_of(foo.ts[1]).bars.should == [] }
      it { foo.as_of(foo.ts[2]).bars.should == [bar] }

      it { foo.as_of(foo.ts[2]).bars.first.name.should == 'foo bar' }


      it { foo.as_of(bar.ts[0]).bars.should == [bar] }
      it { foo.as_of(bar.ts[1]).bars.should == [bar] }
      it { foo.as_of(bar.ts[2]).bars.should == [bar] }
      it { foo.as_of(bar.ts[3]).bars.should == [bar] }

      it { foo.as_of(bar.ts[0]).bars.first.name.should == 'bar' }
      it { foo.as_of(bar.ts[1]).bars.first.name.should == 'foo bar' }
      it { foo.as_of(bar.ts[2]).bars.first.name.should == 'bar bar' }
      it { foo.as_of(bar.ts[3]).bars.first.name.should == 'new bar' }


      it { bar.as_of(bar.ts[0]).foo.should == foo }
      it { bar.as_of(bar.ts[1]).foo.should == foo }
      it { bar.as_of(bar.ts[2]).foo.should == foo }
      it { bar.as_of(bar.ts[3]).foo.should == foo }

      it { bar.as_of(bar.ts[0]).foo.name.should == 'foo bar' }
      it { bar.as_of(bar.ts[1]).foo.name.should == 'foo bar' }
      it { bar.as_of(bar.ts[2]).foo.name.should == 'new foo' }
      it { bar.as_of(bar.ts[3]).foo.name.should == 'new foo' }
    end

    it 'raises RecordNotFound when no history records are found' do
      expect { foo.as_of(1.minute.ago) }.to raise_error
    end
  end

  describe '#history' do
    describe 'returns historical instances' do
      it { foo.history.should have(3).entries }
      it { foo.history.map(&:name).should == ['foo', 'foo bar', 'new foo'] }

      it { bar.history.should have(4).entries }
      it { bar.history.map(&:name).should == ['bar', 'foo bar', 'bar bar', 'new bar'] }
    end

    describe 'returns read only records' do
      it { foo.history.all?(&:readonly?).should be_true }
      it { bar.history.all?(&:readonly?).should be_true }
    end

    describe 'takes care of associated records' do
      subject { foo.history.map {|f| f.bars.first.try(:name)} }
      it { should == [nil, 'foo bar', 'new bar'] }
    end

    describe 'returns read only associated records' do
      it { foo.history[2].bars.all?(&:readonly?).should be_true }
      it { bar.history.all? {|b| b.foo.readonly?}.should be_true }
    end

  end

end
