# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine, :db do
  include ChronoTest::TimeMachine::Helpers

  describe 'includes + joins with as_of' do
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

      it 'works with left_outer_joins' do
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

      it 'works with nested hash includes with has_many associations' do
        # Test the Hash case in assign_as_of_time_to_spec and
        # nested Array case in assign_as_of_time_to_association
        t = $t.foo.ts[1]

        # Using Foo -> bars (has_many) -> sub_bars (has_many)
        # This should trigger both:
        # 1. Hash case: includes(bars: :sub_bars)
        # 2. Array nested case: when propagating to bars array, then to sub_bars
        foo_records = Foo.as_of(t).includes(bars: :sub_bars).joins(:bars)

        # Verify that nested associations maintain as_of_time
        foo_records.each do |foo|
          foo.bars.each do |bar|
            # Verify the bar has the correct as_of_time context
            expect(bar.foo.name).to eq('foo bar') # Historical name, not current

            # Access sub_bars to ensure nested propagation worked
            bar.sub_bars.each do |sub_bar|
              # This traversal should maintain as_of context
              expect(sub_bar.bar.foo.name).to eq('foo bar')
            end
          end
        end
      end

      it 'works with deeply nested hash includes' do
        # Test deeply nested Hash structure to ensure recursive handling
        t = $t.foo.ts[1]

        # This creates a complex nested structure that should hit the Hash case multiple times
        foo_records = Foo.as_of(t).includes(bars: { sub_bars: :sub_sub_bars }).joins(:bars)

        foo_records.each do |foo|
          foo.bars.each do |bar|
            expect(bar.foo.name).to eq('foo bar')
            bar.sub_bars.each do |sub_bar|
              expect(sub_bar.bar.foo.name).to eq('foo bar')
              sub_bar.sub_sub_bars.each do |sub_sub_bar|
                expect(sub_sub_bar.sub_bar.bar.foo.name).to eq('foo bar')
              end
            end
          end
        end
      end

      it 'fixes issue with Arel::Table join nodes when using as_of with nested includes and joins' do
        # This test specifically demonstrates the fix for the reported issue where
        # eager loading via joins/left_outer_joins ignores the as_of timestamp
        # on ChronoModel temporal relations for nested associations.
        t = $t.bar.ts[1]

        # Sanity check: verify historical data differs from current
        historical_foo = Foo.as_of(t).find($t.foo.id)
        current_foo = Foo.find($t.foo.id)
        expect(historical_foo.name).to eq('foo bar')
        expect(current_foo.name).to eq('new foo')

        # Test the specific case that was failing: nested includes with joins
        # where the join target should be replaced with the association klass time-traveled
        # at the same timestamp. This should perform JOIN (...subquery...) instead of JOIN table.
        baz_records = Baz.as_of(t).includes(bar: :foo).joins(bar: :foo)

        baz_records.each do |baz|
          # Before the fix, this would return 'new foo' (current data)
          # After the fix, this correctly returns 'foo bar' (historical data at time t)
          expect(baz.bar.foo.name).to eq('foo bar'),
                 "Expected historical name 'foo bar', got '#{baz.bar.foo.name}'"
        end

        # Also test with left_outer_joins to ensure it works there too
        baz_left_joins = Baz.as_of(t).includes(bar: :foo).left_outer_joins(bar: :foo)
        baz_left_joins.each do |baz|
          expect(baz.bar.foo.name).to eq('foo bar'),
                 "Expected historical name 'foo bar' with left_outer_joins, got '#{baz.bar.foo.name}'"
        end
      end
    end
  end
end
