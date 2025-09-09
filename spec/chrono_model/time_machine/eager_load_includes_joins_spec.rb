# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe 'includes + joins with as_of', :db do
  include ChronoTest::TimeMachine::Helpers

  describe 'propagates as_of_time to eagerly loaded associations used in subsequent traversals' do
    it 'works with includes + joins' do
      # Using Baz -> Bar -> Foo structure from support fixtures
      # Choose a timestamp before Foo rename to ensure history differs from present
      # At $t.bar.ts[1], foo name expected via history is 'foo bar' (see existing specs line 181-182)
      t = $t.bar.ts[1]

      # Sanity: at time t, foo name expected via history is 'foo bar' 
      expect($t.baz.as_of(t).bar.foo.name).to eq 'foo bar'

      # This should return the historical foo name, not the current one
      names = Baz.as_of(t).includes(:bar).joins(:bar).map { |bz| bz.bar.foo.name }.uniq
      expect(names).to eq(['foo bar'])
    end

    it 'works with nested includes' do
      t = $t.bar.ts[1]

      # Test nested includes: includes(bar: :foo)
      names = Baz.as_of(t).includes(bar: :foo).joins(:bar).map { |bz| bz.bar.foo.name }.uniq
      expect(names).to eq(['foo bar'])
    end

    it 'also works with left_outer_joins' do
      t = $t.bar.ts[1]
      names = Baz.as_of(t).includes(:bar).left_outer_joins(:bar).map { |bz| bz.bar.foo.name }.uniq
      expect(names).to eq(['foo bar'])
    end

    it 'works with joins only (baseline check)' do
      t = $t.bar.ts[1]
      names = Baz.as_of(t).joins(:bar).map { |bz| bz.bar.foo.name }.uniq
      expect(names).to eq(['foo bar'])
    end

    it 'works with includes only (baseline check)' do
      t = $t.bar.ts[1]
      names = Baz.includes(:bar).as_of(t).map { |bz| bz.bar.foo.name }.uniq
      expect(names).to eq(['foo bar'])
    end
  end
end