# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine, :db do
  include ChronoTest::TimeMachine::Helpers

  describe 'as_of with eager_load associations' do
    context 'when loading historical associations' do
      # At $t.subbar.ts[0], SubBar was created and associated with $t.bar
      # At that time, $t.bar had name 'foo bar' (from previous update)
      let(:historical_timestamp) { $t.subbar.ts[0] } # When SubBar was first created

      it 'loads the historical associated bar without explicit preloading' do
        historical_sub_bar = SubBar.as_of(historical_timestamp).first
        expect(historical_sub_bar).not_to be_nil
        expect(historical_sub_bar.bar.name).to eq('foo bar')
      end

      it 'loads the historical associated bar with includes (lazy association load)' do
        historical_sub_bar = SubBar.as_of(historical_timestamp).includes(:bar).first
        expect(historical_sub_bar).not_to be_nil
        expect(historical_sub_bar.bar.name).to eq('foo bar')
      end

      it 'loads the historical associated bar with eager_load (inline join)' do
        historical_sub_bar = SubBar.as_of(historical_timestamp).eager_load(:bar).first
        expect(historical_sub_bar).not_to be_nil
        expect(historical_sub_bar.bar.name).to eq('foo bar')
      end
    end
  end
end
