# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

class Country < ActiveRecord::Base
  include ChronoModel::TimeMachine

  has_many :cities
end

class City < ActiveRecord::Base
  include ChronoModel::TimeMachine

  belongs_to :country
end

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe 'historical association' do
    adapter.create_table :countries, temporal: true do |t|
      t.string :name
      t.timestamps
    end

    adapter.create_table :cities, temporal: true do |t|
      t.references :country
      t.string :name
      t.timestamps
    end

    it 'returns historical association at the last time when record is valid' do
      country = Country.create name: 'Country'
      city = country.cities.create name: 'City'

      city.transaction do
        country.update_column :name, 'Country 2'
        city.update_column :name, 'City 2'
      end

      expect(country.history.first.cities.first.name).to eq 'City'
    end
  end
end
