require 'spec_helper'
require 'support/helpers'
require 'spec/chrono_model/time_machine/schema'

describe ChronoModel::TimeMachine do
  include ChronoTest::Helpers::TimeMachine

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


  describe '#history' do
    describe 'returns historical instances' do
      it { expect($t.foo.history.size).to eq(3) }
      it { expect($t.foo.history.map(&:name)).to eq ['foo', 'foo bar', 'new foo'] }

      it { expect($t.bar.history.size).to eq(4) }
      it { expect($t.bar.history.map(&:name)).to eq ['bar', 'foo bar', 'bar bar', 'new bar'] }
    end

    describe 'does not return read only records' do
      it { expect($t.foo.history.all?(&:readonly?)).to be(false) }
      it { expect($t.bar.history.all?(&:readonly?)).to be(false) }
    end

    describe 'takes care of associated records' do
      subject { $t.foo.history.map {|f| f.bars.first.try(:name)} }
      it { is_expected.to eq [nil, 'foo bar', 'new bar'] }
    end

    describe 'does not return read only associated records' do
      it { expect($t.foo.history[2].bars.all?(&:readonly?)).to_not be(true) }
      it { expect($t.bar.history.all? {|b| b.foo.readonly?}).to_not be(true) }
    end

    describe 'allows a custom select list' do
      it { expect($t.foo.history.select(:id).first.attributes.keys).to eq %w( id ) }
    end

    describe 'does not add as_of_time when there are aggregates' do
      it { expect($t.foo.history.select('max(id)').to_sql).to_not match(/as_of_time/) }

      it { expect($t.foo.history.except(:order).select('max(id) as foo, min(id) as bar').group('id').first.attributes.keys).to eq %w( id foo bar ) }
    end

    context '.sorted' do
      describe 'orders by recorded_at, hid' do
        it { expect($t.foo.history.sorted.to_sql).to match(/order by .+"recorded_at" ASC, .+"hid" ASC/i) }
      end
    end
  end


  describe '#current_version' do
    describe 'on plain records' do
      subject { $t.foo.current_version }
      it { is_expected.to eq $t.foo }
    end

    describe 'from #as_of' do
      subject { $t.foo.as_of(Time.now) }
      it { is_expected.to eq $t.foo }
    end

    describe 'on historical records' do
      subject { $t.foo.history.sample.current_version }
      it { is_expected.to eq $t.foo }
    end
  end


  describe '#historical?' do
    subject { record.historical? }

    describe 'on plain records' do
      let(:record) { $t.foo }
      it { is_expected.to be(false) }
    end

    describe 'on historical records' do
      describe 'from #history' do
        let(:record) { $t.foo.history.first }
        it { is_expected.to be(true) }
      end

      describe 'from #as_of' do
        let(:record) { $t.foo.as_of(Time.now) }
        it { is_expected.to be(true) }
      end
    end
  end
end
