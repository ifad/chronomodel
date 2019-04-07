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

  #
  subbar = ts_eval { SubBar.create! :name => 'sub-bar', :bar => bar }
  ts_eval(subbar) { update_attributes! :name => 'bar sub-bar' }

  ts_eval(foo) { update_attributes! :name => 'new foo' }

  ts_eval(bar) { update_attributes! :name => 'bar bar' }
  ts_eval(bar) { update_attributes! :name => 'new bar' }

  ts_eval(subbar) { update_attributes! :name => 'sub-bar sub-bar' }
  ts_eval(subbar) { update_attributes! :name => 'new sub-bar' }

  #
  foos = Array.new(2) {|i| ts_eval { Foo.create! :name => "foo #{i}" } }
  bars = Array.new(2) {|i| ts_eval { Bar.create! :name => "bar #{i}", :foo => foos[i] } }

  #
  baz = Baz.create :name => 'baz', :bar => bar

  # Specs start here
  #
  describe '.chrono?' do
    subject { model.chrono? }

    context 'on a temporal model' do
      let(:model) { Foo }
      it { is_expected.to be(true) }
    end

    context 'on a plain model' do
      let(:model) { Plain }
      it { is_expected.to be(false) }
    end
  end

  describe '.history?' do
    subject { model.history? }

    context 'on a temporal parent model' do
      let(:model) { Foo }
      it { is_expected.to be(false) }
    end

    context 'on a temporal history model' do
      let(:model) { Foo::History }
      it { is_expected.to be(true) }
    end

    context 'on a plain model' do
      let(:model) { Plain }
      it { expect { subject }.to raise_error(NoMethodError) }
    end
  end

  describe '.descendants' do
    subject { Element.descendants }
    it { is_expected.to_not include(Element::History) }
    it { is_expected.to     include(Publication) }
  end

  describe '.descendants_with_history' do
    subject { Element.descendants_with_history }
    it { is_expected.to include(Element::History) }
    it { is_expected.to include(Publication) }
  end

  describe '.history_models' do
    subject { ChronoModel.history_models }

    it { is_expected.to eq(
      'foos'     => Foo::History,
      'defoos'   => Defoo::History,
      'bars'     => Bar::History,
      'elements' => Element::History,
      'sub_bars' => SubBar::History,
    ) }
  end

  describe 'does not interfere with AR standard behaviour' do
    all_foos = [ foo ] + foos
    all_bars = [ bar ] + bars

    it { expect(Foo.count).to eq all_foos.size }
    it { expect(Bar.count).to eq all_bars.size }

    it { expect(Foo.includes(bars: :sub_bars)).to eq all_foos }
    it { expect(Foo.includes(:bars).preload(bars: :sub_bars)).to eq all_foos }

    it { expect(Foo.includes(:bars).first.name).to eq 'new foo' }
    it { expect(Foo.includes(:bars).as_of(foo.ts[0]).first.name).to eq 'foo' }

    it { expect(Foo.joins(:bars).map(&:bars).flatten).to eq all_bars }
    it { expect(Foo.joins(:bars).first.bars.joins(:sub_bars).first.name).to eq 'new bar' }

    it { expect(Foo.joins(bars: :sub_bars).first.bars.joins(:sub_bars).first.sub_bars.first.name).to eq 'new sub-bar' }

    it { expect(Foo.first.bars.includes(:sub_bars)).to eq [ bar ] }

  end

  describe '#as_of' do
    describe 'accepts a Time instance' do
      it { expect(foo.as_of(Time.now).name).to eq 'new foo' }
      it { expect(bar.as_of(Time.now).name).to eq 'new bar' }
    end

    describe 'ignores time zones' do
      it { expect(foo.as_of(Time.now.in_time_zone('America/Havana')).name).to eq 'new foo' }
      it { expect(bar.as_of(Time.now.in_time_zone('America/Havana')).name).to eq 'new bar' }
    end

    describe 'returns records as they were before' do
      it { expect(foo.as_of(foo.ts[0]).name).to eq 'foo' }
      it { expect(foo.as_of(foo.ts[1]).name).to eq 'foo bar' }
      it { expect(foo.as_of(foo.ts[2]).name).to eq 'new foo' }

      it { expect(bar.as_of(bar.ts[0]).name).to eq 'bar' }
      it { expect(bar.as_of(bar.ts[1]).name).to eq 'foo bar' }
      it { expect(bar.as_of(bar.ts[2]).name).to eq 'bar bar' }
      it { expect(bar.as_of(bar.ts[3]).name).to eq 'new bar' }
    end

    describe 'takes care of associated records' do
      it { expect(foo.as_of(foo.ts[0]).bars).to eq [] }
      it { expect(foo.as_of(foo.ts[1]).bars).to eq [] }
      it { expect(foo.as_of(foo.ts[2]).bars).to eq [bar] }

      it { expect(foo.as_of(foo.ts[2]).bars.first.name).to eq 'foo bar' }


      it { expect(foo.as_of(bar.ts[0]).bars).to eq [bar] }
      it { expect(foo.as_of(bar.ts[1]).bars).to eq [bar] }
      it { expect(foo.as_of(bar.ts[2]).bars).to eq [bar] }
      it { expect(foo.as_of(bar.ts[3]).bars).to eq [bar] }

      it { expect(foo.as_of(bar.ts[0]).bars.first.name).to eq 'bar' }
      it { expect(foo.as_of(bar.ts[1]).bars.first.name).to eq 'foo bar' }
      it { expect(foo.as_of(bar.ts[2]).bars.first.name).to eq 'bar bar' }
      it { expect(foo.as_of(bar.ts[3]).bars.first.name).to eq 'new bar' }


      it { expect(bar.as_of(bar.ts[0]).foo).to eq foo }
      it { expect(bar.as_of(bar.ts[1]).foo).to eq foo }
      it { expect(bar.as_of(bar.ts[2]).foo).to eq foo }
      it { expect(bar.as_of(bar.ts[3]).foo).to eq foo }

      it { expect(bar.as_of(bar.ts[0]).foo.name).to eq 'foo bar' }
      it { expect(bar.as_of(bar.ts[1]).foo.name).to eq 'foo bar' }
      it { expect(bar.as_of(bar.ts[2]).foo.name).to eq 'new foo' }
      it { expect(bar.as_of(bar.ts[3]).foo.name).to eq 'new foo' }
    end

    describe 'supports historical queries with includes()' do
      it { expect(Foo.as_of(foo.ts[0]).includes(:bars).first.bars).to eq [] }
      it { expect(Foo.as_of(foo.ts[1]).includes(:bars).first.bars).to eq [] }
      it { expect(Foo.as_of(foo.ts[2]).includes(:bars).first.bars).to eq [bar] }

      it { expect(Foo.as_of(bar.ts[0]).includes(:bars).first.bars.first.name).to eq 'bar' }
      it { expect(Foo.as_of(bar.ts[1]).includes(:bars).first.bars.first.name).to eq 'foo bar' }
      it { expect(Foo.as_of(bar.ts[2]).includes(:bars).first.bars.first.name).to eq 'bar bar' }
      it { expect(Foo.as_of(bar.ts[3]).includes(:bars).first.bars.first.name).to eq 'new bar' }


      it { expect(Foo.as_of(foo.ts[0]).includes(bars: :sub_bars).first.bars).to eq [] }
      it { expect(Foo.as_of(foo.ts[1]).includes(bars: :sub_bars).first.bars).to eq [] }
      it { expect(Foo.as_of(foo.ts[2]).includes(bars: :sub_bars).first.bars).to eq [bar] }

      it { expect(Foo.as_of(bar.ts[0]).includes(bars: :sub_bars).first.bars.first.name).to eq 'bar' }
      it { expect(Foo.as_of(bar.ts[1]).includes(bars: :sub_bars).first.bars.first.name).to eq 'foo bar' }
      it { expect(Foo.as_of(bar.ts[2]).includes(bars: :sub_bars).first.bars.first.name).to eq 'bar bar' }
      it { expect(Foo.as_of(bar.ts[3]).includes(bars: :sub_bars).first.bars.first.name).to eq 'new bar' }


      it { expect(Bar.as_of(bar.ts[0]).includes(:foo).first.foo).to eq foo }
      it { expect(Bar.as_of(bar.ts[1]).includes(:foo).first.foo).to eq foo }
      it { expect(Bar.as_of(bar.ts[2]).includes(:foo).first.foo).to eq foo }
      it { expect(Bar.as_of(bar.ts[3]).includes(:foo).first.foo).to eq foo }

      it { expect(Bar.as_of(bar.ts[0]).includes(:foo).first.foo.name).to eq 'foo bar' }
      it { expect(Bar.as_of(bar.ts[1]).includes(:foo).first.foo.name).to eq 'foo bar' }
      it { expect(Bar.as_of(bar.ts[2]).includes(:foo).first.foo.name).to eq 'new foo' }
      it { expect(Bar.as_of(bar.ts[3]).includes(:foo).first.foo.name).to eq 'new foo' }


      it { expect(Bar.as_of(bar.ts[0]).includes(foo: :sub_bars).first.foo).to eq foo }
      it { expect(Bar.as_of(bar.ts[1]).includes(foo: :sub_bars).first.foo).to eq foo }
      it { expect(Bar.as_of(bar.ts[2]).includes(foo: :sub_bars).first.foo).to eq foo }
      it { expect(Bar.as_of(bar.ts[3]).includes(foo: :sub_bars).first.foo).to eq foo }

      it { expect(Bar.as_of(bar.ts[0]).includes(foo: :sub_bars).first.foo.name).to eq 'foo bar' }
      it { expect(Bar.as_of(bar.ts[1]).includes(foo: :sub_bars).first.foo.name).to eq 'foo bar' }
      it { expect(Bar.as_of(bar.ts[2]).includes(foo: :sub_bars).first.foo.name).to eq 'new foo' }
      it { expect(Bar.as_of(bar.ts[3]).includes(foo: :sub_bars).first.foo.name).to eq 'new foo' }

      it { expect(Foo.as_of(foo.ts[0]).includes(:bars, :sub_bars).first.sub_bars.count).to eq 0 }
      it { expect(Foo.as_of(foo.ts[1]).includes(:bars, :sub_bars).first.sub_bars.count).to eq 0 }
      it { expect(Foo.as_of(foo.ts[2]).includes(:bars, :sub_bars).first.sub_bars.count).to eq 1 }

      it { expect(Foo.as_of(foo.ts[0]).includes(:bars, :sub_bars).first.sub_bars.first).to be nil }
      it { expect(Foo.as_of(foo.ts[1]).includes(:bars, :sub_bars).first.sub_bars.first).to be nil }

      it { expect(Foo.as_of(subbar.ts[0]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'sub-bar' }
      it { expect(Foo.as_of(subbar.ts[1]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'bar sub-bar' }
      it { expect(Foo.as_of(subbar.ts[2]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'sub-bar sub-bar' }
      it { expect(Foo.as_of(subbar.ts[3]).includes(:bars, :sub_bars).first.sub_bars.first.name).to eq 'new sub-bar' }
    end

    it 'doesn\'t raise RecordNotFound when no history records are found' do
      expect { foo.as_of(1.minute.ago) }.to_not raise_error
      expect(foo.as_of(1.minute.ago)).to be(nil)
    end


    it 'raises ActiveRecord::RecordNotFound in the bang variant' do
      expect { foo.as_of!(1.minute.ago) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    describe 'it honors default_scopes' do
      active = ts_eval { Defoo.create! :name => 'active 1', :active => true }
      ts_eval(active) { update_attributes! :name => 'active 2' }

      hidden = ts_eval { Defoo.create! :name => 'hidden 1', :active => false }
      ts_eval(hidden) { update_attributes! :name => 'hidden 2' }

      it { expect(Defoo.as_of(active.ts[0]).map(&:name)).to eq ['active 1'] }
      it { expect(Defoo.as_of(active.ts[1]).map(&:name)).to eq ['active 2'] }
      it { expect(Defoo.as_of(hidden.ts[0]).map(&:name)).to eq ['active 2'] }
      it { expect(Defoo.as_of(hidden.ts[1]).map(&:name)).to eq ['active 2'] }

      it { expect(Defoo.unscoped.as_of(active.ts[0]).map(&:name)).to eq ['active 1'] }
      it { expect(Defoo.unscoped.as_of(active.ts[1]).map(&:name)).to eq ['active 2'] }
      it { expect(Defoo.unscoped.as_of(hidden.ts[0]).map(&:name)).to eq ['active 2', 'hidden 1'] }
      it { expect(Defoo.unscoped.as_of(hidden.ts[1]).map(&:name)).to eq ['active 2', 'hidden 2'] }
    end

    describe 'proxies from non-temporal models to temporal ones' do
      it { expect(baz.as_of(bar.ts[0]).name).to eq 'baz' }
      it { expect(baz.as_of(bar.ts[1]).name).to eq 'baz' }
      it { expect(baz.as_of(bar.ts[2]).name).to eq 'baz' }
      it { expect(baz.as_of(bar.ts[3]).name).to eq 'baz' }

      it { expect(baz.as_of(bar.ts[0]).bar.name).to eq 'bar' }
      it { expect(baz.as_of(bar.ts[1]).bar.name).to eq 'foo bar' }
      it { expect(baz.as_of(bar.ts[2]).bar.name).to eq 'bar bar' }
      it { expect(baz.as_of(bar.ts[3]).bar.name).to eq 'new bar' }

      it { expect(baz.as_of(bar.ts[0]).bar.foo.name).to eq 'foo bar' }
      it { expect(baz.as_of(bar.ts[1]).bar.foo.name).to eq 'foo bar' }
      it { expect(baz.as_of(bar.ts[2]).bar.foo.name).to eq 'new foo' }
      it { expect(baz.as_of(bar.ts[3]).bar.foo.name).to eq 'new foo' }
    end
  end

  describe '#history' do
    describe 'returns historical instances' do
      it { expect(foo.history.size).to eq(3) }
      it { expect(foo.history.map(&:name)).to eq ['foo', 'foo bar', 'new foo'] }

      it { expect(bar.history.size).to eq(4) }
      it { expect(bar.history.map(&:name)).to eq ['bar', 'foo bar', 'bar bar', 'new bar'] }
    end

    describe 'does not return read only records' do
      it { expect(foo.history.all?(&:readonly?)).to be(false) }
      it { expect(bar.history.all?(&:readonly?)).to be(false) }
    end

    describe 'takes care of associated records' do
      subject { foo.history.map {|f| f.bars.first.try(:name)} }
      it { is_expected.to eq [nil, 'foo bar', 'new bar'] }
    end

    describe 'does not return read only associated records' do
      it { expect(foo.history[2].bars.all?(&:readonly?)).to_not be(true) }
      it { expect(bar.history.all? {|b| b.foo.readonly?}).to_not be(true) }
    end

    describe 'allows a custom select list' do
      it { expect(foo.history.select(:id).first.attributes.keys).to eq %w( id ) }
    end

    describe 'does not add as_of_time when there are aggregates' do
      it { expect(foo.history.select('max(id)').to_sql).to_not match(/as_of_time/) }

      it { expect(foo.history.except(:order).select('max(id) as foo, min(id) as bar').group('id').first.attributes.keys).to eq %w( id foo bar ) }
    end

    context 'with STI models' do
      pub = ts_eval { Publication.create! :title => 'wrong title' }
      ts_eval(pub) { update_attributes! :title => 'correct title' }

      it { expect(pub.history.map(&:title)).to eq ['wrong title', 'correct title'] }
    end

    context '.sorted' do
      describe 'orders by recorded_at, hid' do
        it { expect(foo.history.sorted.to_sql).to match(/order by .+"recorded_at" ASC, .+"hid" ASC/i) }
      end
    end
  end

  describe '#pred' do
    context 'on the first history entry' do
      subject { foo.history.first.pred }
      it { is_expected.to be(nil) }
    end

    context 'on the second history entry' do
      subject { foo.history.second.pred }
      it { is_expected.to eq foo.history.first }
    end

    context 'on the last history entry' do
      subject { foo.history.last.pred }
      it { is_expected.to eq foo.history[foo.history.size - 2] }
    end
  end

  describe '#succ' do
    context 'on the first history entry' do
      subject { foo.history.first.succ }
      it { is_expected.to eq foo.history.second }
    end

    context 'on the second history entry' do
      subject { foo.history.second.succ }
      it { is_expected.to eq foo.history.third }
    end

    context 'on the last history entry' do
      subject { foo.history.last.succ }
      it { is_expected.to be(nil) }
    end
  end

  describe '#first' do
    subject { foo.history.sample.first }
    it { is_expected.to eq foo.history.first }
  end

  describe '#last' do
    subject { foo.history.sample.last }
    it { is_expected.to eq foo.history.last }
  end

  describe '#current_version' do
    describe 'on plain records' do
      subject { foo.current_version }
      it { is_expected.to eq foo }
    end

    describe 'from #as_of' do
      subject { foo.as_of(Time.now) }
      it { is_expected.to eq foo }
    end

    describe 'on historical records' do
      subject { foo.history.sample.current_version }
      it { is_expected.to eq foo }
    end
  end

  describe '#historical?' do
    subject { record.historical? }

    describe 'on plain records' do
      let(:record) { foo }
      it { is_expected.to be(false) }
    end

    describe 'on historical records' do
      describe 'from #history' do
        let(:record) { foo.history.first }
        it { is_expected.to be(true) }
      end

      describe 'from #as_of' do
        let(:record) { foo.as_of(Time.now) }
        it { is_expected.to be(true) }
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
        subject { record.name }

        context do
          let(:record) { rec.as_of(rec.ts.first) }
          it { is_expected.to eq 'alive foo' }
        end

        context do
          let(:record) { rec.as_of(rec.ts.last) }
          it { is_expected.to eq 'dying foo' }
        end

        context do
          let(:record) { Foo.as_of(rec.ts.first).where(:fooity => 42).first }
          it { is_expected.to eq 'alive foo' }
        end

        context do
          subject { Foo.history.where(:fooity => 42).map(&:name) }
          it { is_expected.to eq ['alive foo', 'dying foo'] }
        end
      end
    end
  end

  describe '#timeline' do
    split = lambda {|ts| ts.map!{|t| [t.to_i, t.usec]} }

    timestamps_from = lambda {|*records|
      records.map(&:history).flatten!.inject([]) {|ret, rec|
        ret.push [rec.valid_from.to_i, rec.valid_from.usec] if rec.try(:valid_from)
        ret.push [rec.valid_to  .to_i, rec.valid_to  .usec] if rec.try(:valid_to)
        ret
      }.sort.uniq
    }

    describe 'on records having an :has_many relationship' do
      describe 'by default returns timestamps of the record only' do
        subject { split.call(foo.timeline) }
        it { expect(subject.size).to eq foo.ts.size }
        it { is_expected.to eq timestamps_from.call(foo) }
      end

      describe 'when asked, returns timestamps including the related objects' do
        subject { split.call(foo.timeline(:with => :bars)) }
        it { expect(subject.size).to eq(foo.ts.size + bar.ts.size) }
        it { is_expected.to eq(timestamps_from.call(foo, *foo.bars)) }
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

        it { expect(subject.size).to eq expected.size }
        it { is_expected.to eq expected }
      end
    end

    describe 'on non-temporal records using has_timeline :with' do
      subject { split.call(baz.timeline) }

      describe 'returns timestamps of its temporal associations' do
        it { expect(subject.size).to eq bar.ts.size }
        it { is_expected.to eq timestamps_from.call(bar) }
      end
    end
  end

  describe '#last_changes' do
    context 'on plain records' do
      context 'having history' do
        subject { bar.last_changes }
        it { is_expected.to eq('name' => ['bar bar', 'new bar']) }
      end

      context 'without history' do
        let(:record) { Bar.create!(:name => 'foreveralone') }
        subject { record.last_changes }
        it { is_expected.to be_nil }
        after { record.destroy.history.delete_all } # UGLY
      end
    end

    context 'on history records' do
      context 'at the beginning of the timeline' do
        subject { bar.history.first.last_changes }
        it { is_expected.to be_nil }
      end

      context 'in the middle of the timeline' do
        subject { bar.history.second.last_changes }
        it { is_expected.to eq('name' => ['bar', 'foo bar']) }
      end
    end
  end

  describe '#changes_against' do
    context 'can compare records against history' do
      it { expect(bar.changes_against(bar.history.first)).to eq('name' => ['bar', 'new bar']) }
      it { expect(bar.changes_against(bar.history.second)).to eq('name' => ['foo bar', 'new bar']) }
      it { expect(bar.changes_against(bar.history.third)).to eq('name' => ['bar bar', 'new bar']) }
      it { expect(bar.changes_against(bar.history.last)).to eq({}) }
    end

    context 'can compare history against history' do
      it { expect(bar.history.first.changes_against(bar.history.third)).to eq('name' => ['bar bar', 'bar']) }
      it { expect(bar.history.second.changes_against(bar.history.third)).to eq('name' => ['bar bar', 'foo bar']) }
      it { expect(bar.history.third.changes_against(bar.history.third)).to eq({}) }
    end
  end

  describe '#pred' do
    context 'on records having history' do
      subject { bar.pred }
      it { expect(subject.name).to eq 'bar bar' }
    end

    context 'when there is enough history' do
      subject { bar.pred.pred.pred.pred }
      it { expect(subject.name).to eq 'bar' }
    end

    context 'when no history is recorded' do
      let(:record) { Bar.create!(:name => 'quuuux') }
      subject { record.pred }
      it { is_expected.to be(nil) }
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

          it { is_expected.to be_present }
          it { is_expected.to be_a(Time) }
          it { is_expected.to be_utc }
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

          it { is_expected.to be(nil) }
        end
      end
    end

  end

  # Class methods
  context do
    describe '.as_of' do
      it { expect(Foo.as_of(1.month.ago)).to eq [] }

      it { expect(Foo.as_of(foos[0].ts[0])).to eq [foo, foos[0]] }
      it { expect(Foo.as_of(foos[1].ts[0])).to eq [foo, foos[0], foos[1]] }
      it { expect(Foo.as_of(Time.now     )).to eq [foo, foos[0], foos[1]] }

      it { expect(Bar.as_of(foos[1].ts[0])).to eq [bar] }

      it { expect(Bar.as_of(bars[0].ts[0])).to eq [bar, bars[0]] }
      it { expect(Bar.as_of(bars[1].ts[0])).to eq [bar, bars[0], bars[1]] }
      it { expect(Bar.as_of(Time.now     )).to eq [bar, bars[0], bars[1]] }

      # Associations
      context do
        subject { foos[0].id }

        it { expect(Foo.as_of(foos[0].ts[0]).find(subject).bars).to eq [] }
        it { expect(Foo.as_of(foos[1].ts[0]).find(subject).bars).to eq [] }
        it { expect(Foo.as_of(bars[0].ts[0]).find(subject).bars).to eq [bars[0]] }
        it { expect(Foo.as_of(bars[1].ts[0]).find(subject).bars).to eq [bars[0]] }
        it { expect(Foo.as_of(Time.now     ).find(subject).bars).to eq [bars[0]] }
      end

      context do
        subject { foos[1].id }

        it { expect { Foo.as_of(foos[0].ts[0]).find(subject) }.to raise_error(ActiveRecord::RecordNotFound) }
        it { expect { Foo.as_of(foos[1].ts[0]).find(subject) }.to_not raise_error }

        it { expect(Foo.as_of(bars[0].ts[0]).find(subject).bars).to eq [] }
        it { expect(Foo.as_of(bars[1].ts[0]).find(subject).bars).to eq [bars[1]] }
        it { expect(Foo.as_of(Time.now     ).find(subject).bars).to eq [bars[1]] }
      end
    end

    describe '.history' do
      let(:foo_history) {
        ['foo', 'foo bar', 'new foo', 'foo 0', 'foo 1']
      }

      let(:bar_history) {
        ['bar', 'foo bar', 'bar bar', 'new bar', 'bar 0', 'bar 1']
      }

      it { expect(Foo.history.all.map(&:name)).to eq foo_history }
      it { expect(Bar.history.all.map(&:name)).to eq bar_history }
    end

    describe '.time_query' do
      it { expect(Foo.history.time_query(:after,  :now, inclusive: true ).count).to eq 3 }
      it { expect(Foo.history.time_query(:after,  :now, inclusive: false).count).to eq 0 }
      it { expect(Foo.history.time_query(:before, :now, inclusive: true ).count).to eq 5 }
      it { expect(Foo.history.time_query(:before, :now, inclusive: false).count).to eq 2 }

      it { expect(Foo.history.past.size).to eq 2 }
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
        expect(r1.history.size).to eq(2)

        expect(r1.history.first.name).to eq 'xact test'
        expect(r1.history.last.name).to  eq 'does work'
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
        expect(r2.history.size).to eq(1)
        expect(r2.history.first.name).to eq 'I am Foo'
      end
    end

    context 'insertion and subsequent deletion' do
      let!(:r3) do
        Foo.transaction do
          Foo.create!(:name => 'it never happened').destroy
        end
      end

      it 'does not generate any history' do
        expect(Foo.history.where(:id => r3.id)).to be_empty
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

      it { is_expected.to be_a(Bar::History) }
      it { expect(subject.name).to eq 'modified bar history' }
    end

    describe '#save!' do
      subject { bar.history.second }

      before do
        subject.name = 'another modified bar history'
        subject.save
        subject.reload
      end

      it { is_expected.to be_a(Bar::History) }
      it { expect(subject.name).to eq 'another modified bar history' }
    end
  end

end
