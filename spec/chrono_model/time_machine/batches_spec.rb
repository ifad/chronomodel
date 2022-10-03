require 'spec_helper'
require 'support/time_machine/structure'

describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '.in_batches' do
    let(:foo_in_batches_of_two) {
      [
        ['new foo', 'foo 0'],
        ['foo 1']
      ]
    }

    let(:foo_history_in_batches_of_two) {
      [
        ['foo', 'foo bar'],
        ['new foo', 'foo 0'],
        ['foo 1']
      ]
    }

    it { expect(Foo.in_batches(of: 2).map { |g| g.map(&:name) }).to eq foo_in_batches_of_two }
    it { expect(Foo.history.in_batches(of: 2).map { |g| g.map(&:name) }).to eq foo_history_in_batches_of_two }
    it { expect(Foo::History.in_batches(of: 2).map { |g| g.map(&:name) }).to eq foo_history_in_batches_of_two }
  end
end
