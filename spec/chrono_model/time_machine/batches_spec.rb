# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe '.find_each' do
    it { expect(Foo.history.find_each(batch_size: 2).count).to eq Foo.history.count }
  end

  describe '.in_batches' do
    let(:foo_in_batches_of_two) do
      [
        ['new foo', 'foo 0'],
        ['foo 1']
      ]
    end

    let(:foo_history_in_batches_of_two) do
      [
        ['foo', 'foo bar'],
        ['new foo', 'foo 0'],
        ['foo 1']
      ]
    end

    it { expect(Foo.in_batches(of: 2).map { |g| g.map(&:name) }).to eq foo_in_batches_of_two }
    it { expect(Foo.history.in_batches(of: 2).map { |g| g.map(&:name) }).to eq foo_history_in_batches_of_two }
    it { expect(Foo::History.in_batches(of: 2).map { |g| g.map(&:name) }).to eq foo_history_in_batches_of_two }
  end
end
