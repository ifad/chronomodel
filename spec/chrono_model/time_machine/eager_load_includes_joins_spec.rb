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

      it 'attempts to cover Hash case in assign_as_of_time_to_spec' do
        # Test the Hash case: when includes spec is a Hash like {bar: :foo}
        # Note: This test attempts to trigger the Hash case but may not succeed
        # due to Rails' eager loading optimizations and test data constraints
        t = $t.bar.ts[1]

        baz_records = Baz.as_of(t).includes(bar: :foo).joins(:bar)
        names = baz_records.map { |bz| bz.bar.foo.name }.uniq
        expect(names).to eq(['foo bar'])
      end

      it 'attempts to cover Array nested case in assign_as_of_time_to_association' do
        # Test the nested Array case: Array target with nested includes
        # Note: This test attempts to trigger the nested Array case but may not succeed
        # due to Rails' eager loading behavior and the specific conditions required
        t = $t.foo.ts[1]

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
    end
  end
end
