require 'spec_helper'
require 'support/helpers'
require 'spec/chrono_model/time_machine/schema'

describe ChronoModel do
  describe '.history_models' do
    subject { ChronoModel.history_models }

    it 'tracks recorded history models' do
      expected = {}

      expected['foos']     = Foo::History     if defined?(Foo::History)
      expected['defoos']   = Defoo::History   if defined?(Defoo::History)
      expected['bars']     = Bar::History     if defined?(Bar::History)
      expected['sub_bars'] = SubBar::History  if defined?(SubBar::History)

      expected['sections'] = Section::History if defined?(Section::History)
      expected['articles'] = Article::History if defined?(Article::History)

      expected['animals']  = Animal::History  if defined?(Animal::History)
      expected['elements'] = Element::History if defined?(Element::History)

      is_expected.to eq(expected)
    end

    it { expect(subject.size).to be > 0 }
  end
end
