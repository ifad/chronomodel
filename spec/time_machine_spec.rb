require 'spec_helper'
require 'support/helpers'

describe ChronoModel::TimeMachine do
  include ChronoTest::Helpers::TimeMachine

  setup_schema!
  define_models!

  describe '.chrono_models' do
    subject { ChronoModel::TimeMachine.chrono_models }

    it { should == {
      'foos'     => Foo::History,
      'defoos'   => Defoo::History,
      'bars'     => Bar::History,
      'elements' => Element::History
    } }
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

  let!(:baz) {
    Baz.create :name => 'baz', :bar => bar
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

    describe 'it honors default_scopes' do
      let!(:active) {
        active = ts_eval { Defoo.create! :name => 'active 1', :active => true }
        ts_eval(active) { update_attributes! :name => 'active 2' }
      }

      let!(:hidden) {
        hidden = ts_eval { Defoo.create! :name => 'hidden 1', :active => false }
        ts_eval(hidden) { update_attributes! :name => 'hidden 2' }
      }

      it { Defoo.as_of(active.ts[0]).map(&:name).should == ['active 1'] }
      it { Defoo.as_of(active.ts[1]).map(&:name).should == ['active 2'] }
      it { Defoo.as_of(hidden.ts[0]).map(&:name).should == ['active 2'] }
      it { Defoo.as_of(hidden.ts[1]).map(&:name).should == ['active 2'] }

      it { Defoo.unscoped.as_of(active.ts[0]).map(&:name).should == ['active 1'] }
      it { Defoo.unscoped.as_of(active.ts[1]).map(&:name).should == ['active 2'] }
      it { Defoo.unscoped.as_of(hidden.ts[0]).map(&:name).should == ['active 2', 'hidden 1'] }
      it { Defoo.unscoped.as_of(hidden.ts[1]).map(&:name).should == ['active 2', 'hidden 2'] }
    end

    describe 'proxies from non-temporal models to temporal ones' do
      it { baz.as_of(bar.ts[0]).name.should == 'baz' }
      it { baz.as_of(bar.ts[1]).name.should == 'baz' }
      it { baz.as_of(bar.ts[2]).name.should == 'baz' }
      it { baz.as_of(bar.ts[3]).name.should == 'baz' }

      it { baz.as_of(bar.ts[0]).bar.name.should == 'bar' }
      it { baz.as_of(bar.ts[1]).bar.name.should == 'foo bar' }
      it { baz.as_of(bar.ts[2]).bar.name.should == 'bar bar' }
      it { baz.as_of(bar.ts[3]).bar.name.should == 'new bar' }

      it { baz.as_of(bar.ts[0]).bar.foo.name.should == 'foo bar' }
      it { baz.as_of(bar.ts[1]).bar.foo.name.should == 'foo bar' }
      it { baz.as_of(bar.ts[2]).bar.foo.name.should == 'new foo' }
      it { baz.as_of(bar.ts[3]).bar.foo.name.should == 'new foo' }
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

    describe 'allows a custom select list' do
      it { foo.history.select(:id).first.attributes.keys.should == %w( id as_of_time ) }
    end

    describe 'does not add as_of_time when there are aggregates' do
      it { foo.history.select('max (id)').to_sql.should_not =~ /as_of_time/ }
      it { foo.history.select('max (id) as foo, min(id) as bar').first.attributes.keys.should == %w( foo bar ) }
    end

    describe 'orders by recorded_at, hid by default' do
      it { foo.history.to_sql.should =~ /order by.*recorded_at,.*hid/i }
    end

    describe 'allows a custom order list' do
      it { expect { foo.history.order('id') }.to_not raise_error }
      it { foo.history.order('id').to_sql.should =~ /order by id/i }
    end

    context 'with STI models' do
      let!(:pub) {
        pub = ts_eval { Publication.create! :title => 'wrong title' }
        ts_eval(pub) { update_attributes! :title => 'correct title' }
      }

      it { pub.history.map(&:title).should == ['wrong title', 'correct title'] }
    end
  end

  describe '#pred' do
    context 'on the first history entry' do
      subject { foo.history.first.pred }
      it { should be_nil }
    end

    context 'on the second history entry' do
      subject { foo.history.second.pred }
      it { should == foo.history.first }
    end

    context 'on the last history entry' do
      subject { foo.history.last.pred }
      it { should == foo.history[foo.history.size - 2] }
    end
  end

  describe '#succ' do
    context 'on the first history entry' do
      subject { foo.history.first.succ }
      it { should == foo.history.second }
    end

    context 'on the second history entry' do
      subject { foo.history.second.succ }
      it { should == foo.history.third }
    end

    context 'on the last history entry' do
      subject { foo.history.last.succ }
      it { should be_nil }
    end
  end

  describe '#first' do
    subject { foo.history.sample.first }
    it { should == foo.history.first }
  end

  describe '#last' do
    subject { foo.history.sample.last }
    it { should == foo.history.last }
  end

  describe '#record' do
    subject { foo.history.sample.record }
    it { should == foo }
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
      describe 'by default returns timestamps of the record only' do
        subject { foo.history_timestamps }
        its(:size) { should == foo.ts.size }
        it { should == timestamps_from.call(foo) }
      end

      describe 'when asked, returns timestamps including the related objects' do
        subject { foo.history_timestamps(:with => :bars) }
        its(:size) { should == foo.ts.size + bar.ts.size }
        it { should == timestamps_from.call(foo, *foo.bars) }
      end
    end

    describe 'on records having a :belongs_to relationship' do
      subject { bar.history_timestamps }

      describe 'returns timestamps of the record and its associations' do
        its(:size) { should == foo.ts.size + bar.ts.size }
        it { should == timestamps_from.call(foo, bar) }
      end
    end

    describe 'on non-temporal records with a :belongs_to' do
      subject { baz.history_timestamps }

      describe 'returns timestamps of its temporal associations' do
        its(:size) { should == bar.ts.size }
        it { should == timestamps_from.call(bar) }
      end
    end
  end

  describe '#last_changes' do
    context 'on plain records' do
      context 'having history' do
        subject { bar.last_changes }
        it { should == {'name' => ['bar bar', 'new bar']} }
      end

      context 'without history' do
        let(:record) { Bar.create!(:name => 'foreveralone') }
        subject { record.last_changes }
        it { should be_nil }
        after { record.destroy.history.delete_all } # UGLY
      end
    end

    context 'on history records' do
      context 'at the beginning of the timeline' do
        subject { bar.history.first.last_changes }
        it { should be_nil }
      end

      context 'in the middle of the timeline' do
        subject { bar.history.second.last_changes }
        it { should == {'name' => ['bar', 'foo bar']} }
      end
    end
  end

  describe '#changes_against' do
    context 'can compare records against history' do
      it { bar.changes_against(bar.history.first).should ==
             {'name' => ['bar', 'new bar']} }

      it { bar.changes_against(bar.history.second).should ==
             {'name' => ['foo bar', 'new bar']} }

      it { bar.changes_against(bar.history.third).should ==
             {'name' => ['bar bar', 'new bar']} }

      it { bar.changes_against(bar.history.last).should == {} }
    end

    context 'can compare history against history' do
      it { bar.history.first.changes_against(bar.history.third).should ==
             {'name' => ['bar bar', 'bar']} }

      it { bar.history.second.changes_against(bar.history.third).should ==
             {'name' => ['bar bar', 'foo bar']} }

      it { bar.history.third.changes_against(bar.history.third).should == {} }
    end
  end

  describe '#pred' do
    context 'on records having history' do
      subject { bar.pred }
      its(:name) { should == 'bar bar' }
    end

    context 'when there is enough history' do
      subject { bar.pred.pred.pred }
      its(:name) { should == 'bar' }
    end

    context 'when no history is recorded' do
      let(:record) { Bar.create!(:name => 'quuuux') }
      subject { record.pred }
      it { should be_nil }
      after { record.destroy.history.delete_all }
    end
  end

  context do
    let!(:history) { foo.history.first }
    let!(:current) { foo }

    spec = lambda {|attr|
      return lambda {|*|
        describe 'on history records' do
          subject { history.public_send(attr) }

          it { should be_present }
          it { should be_a(Time) }
          it { should be_utc }
        end

        describe 'on current records' do
          subject { current.public_send(attr) }
          it { expect { subject }.to raise_error(NoMethodError) }
        end
      }
    }

    %w( valid_from valid_to recorded_at as_of_time ).each do |attr|
      describe ['#', attr].join, &spec.call(attr)
    end
  end

  # Class methods
  context do
    let!(:foos) { Array.new(2) {|i| ts_eval { Foo.create! :name => "foo #{i}" } } }
    let!(:bars) { Array.new(2) {|i| ts_eval { Bar.create! :name => "bar #{i}", :foo => foos[i] } } }

    after(:all) { foos.each(&:destroy); bars.each(&:destroy) }

    describe '.as_of' do
      it { Foo.as_of(1.month.ago).should == [] }

      it { Foo.as_of(foos[0].ts[0]).should == [foo, foos[0]] }
      it { Foo.as_of(foos[1].ts[0]).should == [foo, foos[0], foos[1]] }
      it { Foo.as_of(Time.now     ).should == [foo, foos[0], foos[1]] }

      it { Bar.as_of(foos[1].ts[0]).should == [bar] }

      it { Bar.as_of(bars[0].ts[0]).should == [bar, bars[0]] }
      it { Bar.as_of(bars[1].ts[0]).should == [bar, bars[0], bars[1]] }
      it { Bar.as_of(Time.now     ).should == [bar, bars[0], bars[1]] }

      # Associations
      context do
        subject { foos[0] }

        it { Foo.as_of(foos[0].ts[0]).find(subject).bars.should == [] }
        it { Foo.as_of(foos[1].ts[0]).find(subject).bars.should == [] }
        it { Foo.as_of(bars[0].ts[0]).find(subject).bars.should == [bars[0]] }
        it { Foo.as_of(bars[1].ts[0]).find(subject).bars.should == [bars[0]] }
        it { Foo.as_of(Time.now     ).find(subject).bars.should == [bars[0]] }
      end

      context do
        subject { foos[1] }

        it { expect { Foo.as_of(foos[0].ts[0]).find(subject) }.to raise_error(ActiveRecord::RecordNotFound) }
        it { expect { Foo.as_of(foos[1].ts[0]).find(subject) }.to_not raise_error }

        it { Foo.as_of(bars[0].ts[0]).find(subject).bars.should == [] }
        it { Foo.as_of(bars[1].ts[0]).find(subject).bars.should == [bars[1]] }
        it { Foo.as_of(Time.now     ).find(subject).bars.should == [bars[1]] }
      end
    end

    describe '.history' do
      let(:foo_history) {
        ['foo', 'foo bar', 'new foo', 'alive foo', 'dying foo', 'foo 0', 'foo 1']
      }

      let(:bar_history) {
        ['bar', 'foo bar', 'bar bar', 'new bar', 'bar 0', 'bar 1']
      }

      it { Foo.history.all.map(&:name).should == foo_history }
      it { Bar.history.all.map(&:name).should == bar_history }
    end
  end

  # Transactions
  context 'Within transactions' do
    context 'multiple updates to an existing record' do
      let!(:r1) do
        Foo.create!(:name => 'xact test').tap do |record|
          Foo.transaction do
            record.update_attribute 'name', 'lost into oblivion'
            record.update_attribute 'name', 'does work'
          end
        end
      end

      it "generate only a single history record" do
        r1.history.should have(2).entries

        r1.history.first.name.should == 'xact test'
        r1.history.last.name.should  == 'does work'
      end
    end

    context 'insertion and subsequent update' do
      let!(:r2) do
        Foo.transaction do
          Foo.create!(:name => 'lost into oblivion').tap do |record|
            record.update_attribute 'name', 'I am Bar'
            record.update_attribute 'name', 'I am Foo'
          end
        end
      end

      it 'generates a single history record' do
        r2.history.should have(1).entry

        r2.history.first.name.should == 'I am Foo'
      end
    end

    context 'insertion and subsequent deletion' do
      let!(:r3) do
        Foo.transaction do
          Foo.create!(:name => 'it never happened').destroy
        end
      end

      it 'does not generate any history' do
        Foo.history.where(:id => r3.id).should be_empty
      end
    end
  end

end
