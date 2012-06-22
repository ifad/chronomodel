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

  describe '#historical?' do
    describe 'on plain records' do
      subject { foo.historical? }
      it { should be_false }
    end

    describe 'on historical records' do
      describe 'from #history' do
        subject { foo.history.first }
        it { should be_true }
      end

      describe 'from #as_of' do
        subject { foo.as_of(Time.now) }
        it { should be_true }
      end
    end
  end

  describe '#destroy' do
    describe 'on historical records' do
      subject { foo.history.first.destroy }
      it { expect { subject }.to raise_error(ActiveRecord::ReadOnlyRecord) }
    end

    describe 'on current records' do
      let!(:rec) {
        rec = ts_eval { Foo.create!(:name => 'alive foo', :fooity => 42) }
        ts_eval(rec) { update_attributes!(:name => 'dying foo') }
      }

      subject { rec.destroy }

      it { expect { subject }.to_not raise_error }
      it { expect { rec.reload }.to raise_error(ActiveRecord::RecordNotFound) }

      describe 'does not delete its history' do
        context do
          subject { rec.as_of(rec.ts.first) }
          its(:name) { should == 'alive foo' }
        end

        context do
          subject { rec.as_of(rec.ts.last) }
          its(:name) { should == 'dying foo' }
        end

        context do
          subject { Foo.as_of(rec.ts.first).where(:fooity => 42).first }
          its(:name) { should == 'alive foo' }
        end

        context do
          subject { Foo.history.where(:fooity => 42).map(&:name) }
          it { should == ['alive foo', 'dying foo'] }
        end
      end
    end
  end

  describe '#history_timestamps' do
    timestamps_from = lambda {|*records|
      records.map(&:history).flatten!.inject([]) {|ret, rec|
        ret.concat [rec.valid_from, rec.valid_to]
      }.sort.uniq[0..-2]
    }

    describe 'on records having an :has_many relationship' do
      subject { foo.history_timestamps }

      describe 'returns timestamps of the record and its associations' do
        its(:size) { should == foo.ts.size + bar.ts.size }
        it { should == timestamps_from.call(foo, bar) }
      end
    end

    describe 'on records having a :belongs_to relationship' do
      subject { bar.history_timestamps }

      describe 'returns timestamps of the record only' do
        its(:size) { should == bar.ts.size }
        it { should == timestamps_from.call(bar) }
      end
    end
  end

  context do
    history_attrs = ChronoModel::TimeMachine::HISTORY_ATTRIBUTES

    let!(:history) { foo.history.first }
    let!(:current) { foo }

    history_attrs.each do |attr|
      describe ['#', attr].join do
        describe 'on history records' do
          subject { history.public_send(attr) }

          it { should be_present }
          it { should be_a(Time) }
          it { should be_utc }
        end

        describe 'on current records' do
          subject { current.public_send(attr) }
          it { should be_nil }
        end
      end
    end

    describe '#initialize_dup' do
      describe 'on history records' do
        subject { history.dup }

        history_attrs.each do |attr|
          its(attr) { should be_nil }
        end

        it { should_not be_readonly }
        it { should be_new_record }

      end
    end
  end

end
