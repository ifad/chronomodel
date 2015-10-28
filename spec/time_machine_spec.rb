require 'spec_helper'
require 'support/helpers'

describe ChronoModel::TimeMachine do
  include ChronoTest::Helpers::TimeMachine

  setup_schema!
  define_models!

  # Set up two associated records, with intertwined updates
  #
  foo = ts_eval { Foo.create! :name => 'foo', :fooity => 1 }
  ts_eval(foo) { update_attributes! :name => 'foo bar' }

  #
  bar = ts_eval { Bar.create! :name => 'bar', :foo => foo }
  ts_eval(bar) { update_attributes! :name => 'foo bar' }

  ts_eval(foo) { update_attributes! :name => 'new foo' }

  ts_eval(bar) { update_attributes! :name => 'bar bar' }
  ts_eval(bar) { update_attributes! :name => 'new bar' }

  #
  baz = Baz.create :name => 'baz', :bar => bar

  describe '.chrono?' do
    subject { model.chrono? }

    context 'on a temporal model' do
      let(:model) { Foo }
      it { should be(true) }
    end

    context 'on a plain model' do
      let(:model) { Plain }
      it { should be(false) }
    end
  end

  describe '.history?' do
    subject { model.history? }

    context 'on a temporal parent model' do
      let(:model) { Foo }
      it { should be(false) }
    end

    context 'on a temporal history model' do
      let(:model) { Foo::History }
      it { should be(true) }
    end

    context 'on a plain model' do
      let(:model) { Plain }
      it { expect { subject }.to raise_error(NoMethodError) }
    end
  end

  describe '.descendants' do
    subject { Element.descendants }
    it { should_not include(Element::History) }
    it { should     include(Publication) }
  end

  describe '.descendants_with_history' do
    subject { Element.descendants_with_history }
    it { should include(Element::History) }
    it { should include(Publication) }
  end

  # Specs start here
  #
  describe '.chrono_models' do
    subject { ChronoModel::TimeMachine.chrono_models }

    it { should == {
      'foos'     => Foo::History,
      'defoos'   => Defoo::History,
      'bars'     => Bar::History,
      'elements' => Element::History
    } }
  end

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

    it 'doesn\'t raise RecordNotFound when no history records are found' do
      expect { foo.as_of(1.minute.ago) }.to_not raise_error
      foo.as_of(1.minute.ago).should be_nil
    end


    it 'raises ActiveRecord::RecordNotFound in the bang variant' do
      expect { foo.as_of!(1.minute.ago) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    describe 'it honors default_scopes' do
      active = ts_eval { Defoo.create! :name => 'active 1', :active => true }
      ts_eval(active) { update_attributes! :name => 'active 2' }

      hidden = ts_eval { Defoo.create! :name => 'hidden 1', :active => false }
      ts_eval(hidden) { update_attributes! :name => 'hidden 2' }

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

    describe 'does not return read only records' do
      it { foo.history.all?(&:readonly?).should_not be_true }
      it { bar.history.all?(&:readonly?).should_not be_true }
    end

    describe 'takes care of associated records' do
      subject { foo.history.map {|f| f.bars.first.try(:name)} }
      it { should == [nil, 'foo bar', 'new bar'] }
    end

    describe 'does not return read only associated records' do
      it { foo.history[2].bars.all?(&:readonly?).should_not be_true }
      it { bar.history.all? {|b| b.foo.readonly?}.should_not be_true }
    end

    describe 'allows a custom select list' do
      it { foo.history.select(:id).first.attributes.keys.should == %w( id ) }
    end

    describe 'does not add as_of_time when there are aggregates' do
      it { foo.history.select('max(id)').to_sql.should_not =~ /as_of_time/ }

      it { foo.history.except(:order).select('max(id) as foo, min(id) as bar').group('id').first.attributes.keys.should == %w( id foo bar ) }
    end

    context 'with STI models' do
      pub = ts_eval { Publication.create! :title => 'wrong title' }
      ts_eval(pub) { update_attributes! :title => 'correct title' }

      it { pub.history.map(&:title).should == ['wrong title', 'correct title'] }
    end

    context '.sorted' do
      describe 'orders by recorded_at, hid' do
        it { foo.history.sorted.to_sql.should =~ /order by .+"recorded_at", .+"hid"/i }
      end
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

  describe '#current_version' do
    describe 'on plain records' do
      subject { foo.current_version }
      it { should == foo }
    end

    describe 'from #as_of' do
      subject { foo.as_of(Time.now) }
      it { should == foo }
    end

    describe 'on historical records' do
      subject { foo.history.sample.current_version }
      it { should == foo }
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
      rec = nil
      before(:all) do
        rec = ts_eval { Foo.create!(:name => 'alive foo', :fooity => 42) }
        ts_eval(rec) { update_attributes!(:name => 'dying foo') }
      end
      after(:all) do
        rec.history.delete_all
      end

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

  describe '#timeline' do
    split = lambda {|ts| ts.map!{|t| [t.to_i, t.usec]} }

    timestamps_from = lambda {|*records|
      ts = records.map(&:history).flatten!.inject([]) {|ret, rec|
        ret.push [rec.valid_from.to_i, rec.valid_from.usec] if rec.try(:valid_from)
        ret.push [rec.valid_to  .to_i, rec.valid_to  .usec] if rec.try(:valid_to)
        ret
      }.sort.uniq
    }

    describe 'on records having an :has_many relationship' do
      describe 'by default returns timestamps of the record only' do
        subject { split.call(foo.timeline) }
        its(:size) { should == foo.ts.size }
        it { should == timestamps_from.call(foo) }
      end

      describe 'when asked, returns timestamps including the related objects' do
        subject { split.call(foo.timeline(:with => :bars)) }
        its(:size) { should == foo.ts.size + bar.ts.size }
        it { should == timestamps_from.call(foo, *foo.bars) }
      end
    end

    describe 'on records using has_timeline :with' do
      subject { split.call(bar.timeline) }

      describe 'returns timestamps of the record and its associations' do

        let!(:expected) do
          creat = bar.history.first.valid_from
          c_sec, c_usec = creat.to_i, creat.usec

          timestamps_from.call(foo, bar).reject {|sec, usec|
            sec < c_sec || ( sec == c_sec && usec < c_usec )
          }
        end

        its(:size) { should == expected.size }
        it { should == expected }
      end
    end

    describe 'on non-temporal records using has_timeline :with' do
      subject { split.call(baz.timeline) }

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
      subject { bar.pred.pred.pred.pred }
      its(:name) { should == 'bar' }
    end

    context 'when no history is recorded' do
      let(:record) { Bar.create!(:name => 'quuuux') }
      subject { record.pred }
      it { should be_nil }
      after { record.destroy.history.delete_all }
    end
  end

  describe 'timestamp methods' do
    history_methods = %w( valid_from valid_to recorded_at )
    current_methods = %w( as_of_time )

    context 'on history records' do
      let(:record) { foo.history.first }

      (history_methods + current_methods).each do |attr|
        describe ['#', attr].join do
          subject { record.public_send(attr) }

          it { should be_present }
          it { should be_a(Time) }
          it { should be_utc }
        end
      end
    end

    context 'on current records' do
      let(:record) { foo }

      history_methods.each do |attr|
        describe ['#', attr].join do
          subject { record.public_send(attr) }

          it { expect { subject }.to raise_error(NoMethodError) }
        end
      end

      current_methods.each do |attr|
        describe ['#', attr].join do
          subject { record.public_send(attr) }

          it { should be_nil }
        end
      end
    end

  end

  # Class methods
  context do
    foos = Array.new(2) {|i| ts_eval { Foo.create! :name => "foo #{i}" } }
    bars = Array.new(2) {|i| ts_eval { Bar.create! :name => "bar #{i}", :foo => foos[i] } }

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
        subject { foos[0].id }

        it { Foo.as_of(foos[0].ts[0]).find(subject).bars.should == [] }
        it { Foo.as_of(foos[1].ts[0]).find(subject).bars.should == [] }
        it { Foo.as_of(bars[0].ts[0]).find(subject).bars.should == [bars[0]] }
        it { Foo.as_of(bars[1].ts[0]).find(subject).bars.should == [bars[0]] }
        it { Foo.as_of(Time.now     ).find(subject).bars.should == [bars[0]] }
      end

      context do
        subject { foos[1].id }

        it { expect { Foo.as_of(foos[0].ts[0]).find(subject) }.to raise_error(ActiveRecord::RecordNotFound) }
        it { expect { Foo.as_of(foos[1].ts[0]).find(subject) }.to_not raise_error }

        it { Foo.as_of(bars[0].ts[0]).find(subject).bars.should == [] }
        it { Foo.as_of(bars[1].ts[0]).find(subject).bars.should == [bars[1]] }
        it { Foo.as_of(Time.now     ).find(subject).bars.should == [bars[1]] }
      end
    end

    describe '.history' do
      let(:foo_history) {
        ['foo', 'foo bar', 'new foo', 'foo 0', 'foo 1']
      }

      let(:bar_history) {
        ['bar', 'foo bar', 'bar bar', 'new bar', 'bar 0', 'bar 1']
      }

      it { Foo.history.all.map(&:name).should == foo_history }
      it { Bar.history.all.map(&:name).should == bar_history }
    end

    describe '.time_query' do
      it { Foo.history.time_query(:after,  :now, inclusive: true ).count.should == 3 }
      it { Foo.history.time_query(:after,  :now, inclusive: false).count.should == 0 }
      it { Foo.history.time_query(:before, :now, inclusive: true ).count.should == 5 }
      it { Foo.history.time_query(:before, :now, inclusive: false).count.should == 2 }

      it { Foo.history.past.size.should == 2 }
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

  # This group is below here to not to disturb the flow of the above specs.
  #
  context 'history modification' do
    describe '#save' do
      subject { bar.history.first }

      before do
        subject.name = 'modified bar history'
        subject.save
        subject.reload
      end

      it { should be_a(Bar::History) }
      it { should be_true }
      its(:name) { should == 'modified bar history' }
    end

    describe '#save!' do
      subject { bar.history.second }

      before do
        subject.name = 'another modified bar history'
        subject.save
        subject.reload
      end

      it { should be_a(Bar::History) }
      it { should be_true }
      its(:name) { should == 'another modified bar history' }
    end
  end

end
