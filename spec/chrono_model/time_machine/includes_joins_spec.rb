# frozen_string_literal: true

require 'spec_helper'

describe ChronoModel::TimeMachine do
  describe 'includes with joins regression' do
    before(:all) do
      # Set up test models similar to the issue description
      adapter.execute <<~SQL
        CREATE TABLE IF NOT EXISTS countries (
          id SERIAL PRIMARY KEY,
          name VARCHAR(255) NOT NULL,
          created_at TIMESTAMP,
          updated_at TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS cities (
          id SERIAL PRIMARY KEY,
          country_id INTEGER REFERENCES countries(id),
          name VARCHAR(255) NOT NULL,
          created_at TIMESTAMP,
          updated_at TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS schools (
          id SERIAL PRIMARY KEY,
          city_id INTEGER REFERENCES cities(id),
          name VARCHAR(255) NOT NULL,
          created_at TIMESTAMP,
          updated_at TIMESTAMP
        );
      SQL

      # Make tables temporal
      adapter.create_temporal_table :countries, temporal: true
      adapter.create_temporal_table :cities, temporal: true  
      adapter.create_temporal_table :schools, temporal: true
    end

    after(:all) do
      # Cleanup
      adapter.drop_temporal_table(:schools) if adapter.table_exists?(:schools)
      adapter.drop_temporal_table(:cities) if adapter.table_exists?(:cities)
      adapter.drop_temporal_table(:countries) if adapter.table_exists?(:countries)
    end

    # Define test models
    let(:country_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'countries'
        include ChronoModel::TimeMachine
        has_many :cities, dependent: :destroy, class_name: city_class_name
        has_many :schools, through: :cities, class_name: school_class_name
        validates :name, presence: true
      end
    end

    let(:city_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'cities'
        include ChronoModel::TimeMachine
        belongs_to :country, class_name: country_class_name
        has_many :schools, dependent: :destroy, class_name: school_class_name
        validates :name, presence: true
      end
    end

    let(:school_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'schools'
        include ChronoModel::TimeMachine
        belongs_to :city, class_name: city_class_name
        has_one :country, through: :city, class_name: country_class_name
        validates :name, presence: true
      end
    end

    let(:country_class_name) { country_class.name }
    let(:city_class_name) { city_class.name }
    let(:school_class_name) { school_class.name }

    let!(:italy) { country_class.create!(name: 'Italy') }
    let!(:rome) { italy.cities.create!(name: 'Rome') }
    let!(:school1) { rome.schools.create!(name: 'G. Galilei') }
    let!(:school2) { rome.schools.create!(name: 'L. Da Vinci') }

    before do
      # Wait a moment then update the country name
      sleep 1
      italy.update!(name: 'Italia')
    end

    describe 'temporal queries with different join strategies' do
      let(:historical_time) { italy.updated_at - 1.second }

      it 'works with joins alone' do
        result = school_class.as_of(historical_time).joins(:city).map { |s| s.city.country.name }.uniq
        expect(result).to eq ['Italy']
      end

      it 'works with includes alone' do
        result = school_class.includes(:city).as_of(historical_time).map { |s| s.city.country.name }.uniq
        expect(result).to eq ['Italy']
      end

      it 'works with includes and left_outer_joins' do
        result = school_class.includes(:city).as_of(historical_time).left_outer_joins(:city).map { |s| s.city.country.name }.uniq
        expect(result).to eq ['Italy']
      end

      it 'should work with includes and joins (this is the failing case)' do
        result = school_class.includes(:city).as_of(historical_time).joins(:city).map { |s| s.city.country.name }.uniq
        expect(result).to eq ['Italy']  # This should pass but currently fails, returning ['Italia']
      end
    end
  end
end