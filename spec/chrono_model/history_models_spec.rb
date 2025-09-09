# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel do
  describe '.history_models' do
    subject(:history_models) { described_class.history_models }

    it 'tracks recorded history models' do
      expected = {}

      # support/time_machine/structure
      expected['foos']     = Foo::History     if defined?(Foo::History)
      expected['bars']     = Bar::History     if defined?(Bar::History)
      expected['moos']     = Moo::History     if defined?(Moo::History)
      expected['boos']     = Boo::History     if defined?(Boo::History)
      expected['noos']     = Noo::History     if defined?(Noo::History)

      expected['sub_bars'] = SubBar::History  if defined?(SubBar::History)
      expected['sub_sub_bars'] = SubSubBar::History if defined?(SubSubBar::History)

      # default_scope_spec
      expected['defoos']   = Defoo::History   if defined?(Defoo::History)

      # counter_cache_race_spec
      expected['sections'] = Section::History if defined?(Section::History)
      expected['articles'] = Article::History if defined?(Article::History)

      # historical_associations_spec
      expected['countries'] = Country::History if defined?(Country::History)
      expected['cities'] = City::History if defined?(City::History)

      # sti_spec
      expected['animals']  = Animal::History  if defined?(Animal::History)
      expected['elements'] = Element::History if defined?(Element::History)

      expect(history_models).to eq(expected)
    end

    it { is_expected.to be_present }
  end
end
