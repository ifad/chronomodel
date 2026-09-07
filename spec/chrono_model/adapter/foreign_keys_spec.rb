# frozen_string_literal: true

require 'spec_helper'
require 'support/matchers/foreign_key'

# Foreign keys on temporal tables are created on the table in the temporal
# schema, and can reference both temporal and plain tables. The history
# tables intentionally carry no foreign keys, so that historical records
# keep referencing data that may have been deleted later on.
#
# See https://github.com/ifad/chronomodel/issues/174
#
RSpec.describe ChronoModel::Adapter do
  include ChronoTest::Matchers::ForeignKey

  delegate :adapter, to: ChronoTest

  let(:temporal_schema) { ChronoModel::Adapter::TEMPORAL_SCHEMA }

  # +regions+ and +countries+ are temporal tables, +cities+ is a plain one.
  #
  let(:regions)   { 'fk_regions' }
  let(:countries) { 'fk_countries' }
  let(:cities)    { 'fk_cities' }

  before do
    adapter.create_table regions, temporal: true do |t|
      t.string :name
    end

    adapter.create_table countries, temporal: true do |t|
      t.string :name
      t.references :fk_region, index: false
      t.references :fk_city,   index: false
    end

    adapter.create_table cities, temporal: false do |t|
      t.string :name
      t.references :fk_region, index: false
    end
  end

  after do
    adapter.drop_table countries
    adapter.drop_table cities
    adapter.drop_table regions
  end

  describe '.add_foreign_key' do
    context 'when both tables are temporal' do
      before { adapter.add_foreign_key countries, regions }

      it { expect(countries).to have_temporal_foreign_key(regions) }
      it { expect(countries).not_to have_history_foreign_key(regions, to_schema: temporal_schema) }
      it { expect(countries).not_to have_foreign_key(regions, to_schema: temporal_schema) }

      it 'is listed by .foreign_keys' do
        expect(adapter.foreign_keys(countries).map(&:to_table)).to include(regions)
      end

      it 'is matched by .foreign_key_exists?' do
        expect(adapter.foreign_key_exists?(countries, regions)).to be(true)
      end

      it 'is matched by .foreign_key_exists? given the referenced table as a keyword' do
        expect(adapter.foreign_key_exists?(countries, to_table: regions)).to be(true)
      end

      it 'enforces referential integrity on the public view' do
        expect do
          adapter.execute "INSERT INTO #{countries} (name, fk_region_id) VALUES ('foo', 0)"
        end.to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end

    context 'when the referenced table is plain' do
      before { adapter.add_foreign_key countries, cities }

      it { expect(countries).to have_temporal_foreign_key(cities, to_schema: 'public') }
      it { expect(countries).not_to have_history_foreign_key(cities, to_schema: 'public') }

      it 'is matched by .foreign_key_exists?' do
        expect(adapter.foreign_key_exists?(countries, cities)).to be(true)
      end
    end

    context 'when the referencing table is plain' do
      before { adapter.add_foreign_key cities, regions }

      it { expect(cities).to have_foreign_key(regions, to_schema: temporal_schema) }

      it 'is matched by .foreign_key_exists?' do
        expect(adapter.foreign_key_exists?(cities, regions)).to be(true)
      end

      it 'is matched by .foreign_key_exists? given the referenced table as a keyword' do
        expect(adapter.foreign_key_exists?(cities, to_table: regions)).to be(true)
      end
    end

    context 'when both tables are plain' do
      before do
        adapter.create_table 'fk_districts', temporal: false do |t|
          t.string :name
        end

        adapter.add_column cities, :fk_district_id, :integer
        adapter.add_foreign_key cities, 'fk_districts'
      end

      after { adapter.drop_table 'fk_districts', force: :cascade }

      it { expect(cities).to have_foreign_key('fk_districts') }
      it { expect(cities).not_to have_temporal_foreign_key('fk_districts') }

      it 'is matched by .foreign_key_exists?' do
        expect(adapter.foreign_key_exists?(cities, 'fk_districts')).to be(true)
      end
    end

    context 'with a custom name and on_delete action' do
      before { adapter.add_foreign_key countries, regions, name: 'countries_regions_fk', on_delete: :cascade }

      it { expect(countries).to have_temporal_foreign_key(regions) }

      it 'is matched by .foreign_key_exists? given its name' do
        expect(adapter.foreign_key_exists?(countries, name: 'countries_regions_fk')).to be(true)
      end

      it 'keeps the given options' do
        foreign_key = adapter.foreign_keys(countries).find { |fk| fk.name == 'countries_regions_fk' }

        expect(foreign_key).to be_present
        expect(foreign_key.to_table).to eq regions
        expect(foreign_key.on_delete).to eq :cascade
        expect(Array(foreign_key.column)).to eq %w[fk_region_id]
      end
    end

    context 'with if_not_exists' do
      before { adapter.add_foreign_key countries, regions }

      it 'does not raise when the key already exists' do
        expect { adapter.add_foreign_key countries, regions, if_not_exists: true }.not_to raise_error
      end

      it 'does not duplicate the key' do
        adapter.add_foreign_key countries, regions, if_not_exists: true

        expect(adapter.foreign_keys(countries).count { |fk| fk.to_table == regions }).to eq 1
      end
    end
  end

  describe '.remove_foreign_key' do
    context 'when both tables are temporal' do
      before { adapter.add_foreign_key countries, regions }

      it 'removes the key given the referenced table' do
        adapter.remove_foreign_key countries, regions

        expect(countries).not_to have_temporal_foreign_key(regions)
      end

      it 'removes the key given its name' do
        name = adapter.foreign_keys(countries).first.name

        adapter.remove_foreign_key countries, name: name

        expect(countries).not_to have_temporal_foreign_key(regions)
      end
    end

    context 'when the referenced table is plain' do
      before do
        adapter.add_foreign_key countries, cities
        adapter.remove_foreign_key countries, cities
      end

      it { expect(countries).not_to have_temporal_foreign_key(cities, to_schema: 'public') }

      it 'is not matched by .foreign_key_exists?' do
        expect(adapter.foreign_key_exists?(countries, cities)).to be(false)
      end
    end

    context 'when the referencing table is plain' do
      before do
        adapter.add_foreign_key cities, regions
        adapter.remove_foreign_key cities, regions
      end

      it { expect(cities).not_to have_foreign_key(regions, to_schema: temporal_schema) }

      it 'is not matched by .foreign_key_exists?' do
        expect(adapter.foreign_key_exists?(cities, regions)).to be(false)
      end
    end

    context 'when both tables are plain' do
      before do
        adapter.create_table 'fk_districts', temporal: false do |t|
          t.string :name
        end

        adapter.add_column cities, :fk_district_id, :integer
        adapter.add_foreign_key cities, 'fk_districts'
        adapter.remove_foreign_key cities, 'fk_districts'
      end

      after { adapter.drop_table 'fk_districts', force: :cascade }

      it { expect(cities).not_to have_foreign_key('fk_districts') }
    end

    context 'with if_exists' do
      it 'does not raise when the key does not exist' do
        expect { adapter.remove_foreign_key countries, regions, if_exists: true }.not_to raise_error
      end
    end
  end

  describe '.create_table with references' do
    let(:orders) { 'fk_orders' }

    after { adapter.drop_table orders }

    it 'supports foreign keys between temporal tables' do
      adapter.create_table orders, temporal: true do |t|
        t.string :name
        t.references :fk_region, foreign_key: { to_table: regions }
      end

      expect(orders).to have_temporal_foreign_key(regions)
      expect(adapter.foreign_key_exists?(orders, regions)).to be(true)
    end
  end

  describe 'references with foreign keys' do
    it 'are added to and removed from temporal tables' do
      adapter.add_reference countries, :capital, foreign_key: { to_table: cities }
      expect(adapter.foreign_key_exists?(countries, cities)).to be(true)

      adapter.remove_reference countries, :capital, foreign_key: { to_table: cities }
      expect(adapter.foreign_key_exists?(countries, cities)).to be(false)
    end

    it 'are added to and removed from plain tables referencing temporal ones' do
      adapter.add_reference cities, :area, foreign_key: { to_table: regions }
      expect(adapter.foreign_key_exists?(cities, regions)).to be(true)

      adapter.remove_reference cities, :area, foreign_key: { to_table: regions }
      expect(adapter.foreign_key_exists?(cities, regions)).to be(false)
    end

    it 'are supported by change_table' do
      adapter.change_table countries do |t|
        t.references :capital, foreign_key: { to_table: cities }
      end

      expect(adapter.foreign_key_exists?(countries, cities, column: :capital_id)).to be(true)
    end
  end

  describe 'schema-qualified table names' do
    it 'supports adding and removing foreign keys' do
      adapter.add_foreign_key "#{temporal_schema}.#{countries}", "#{temporal_schema}.#{regions}"
      expect(countries).to have_temporal_foreign_key(regions)

      adapter.remove_foreign_key "#{temporal_schema}.#{countries}", "#{temporal_schema}.#{regions}"
      expect(countries).not_to have_temporal_foreign_key(regions)
    end

    it 'are equivalent to the bare table names' do
      adapter.add_foreign_key countries, regions

      expect(adapter.foreign_key_exists?("#{temporal_schema}.#{countries}", "#{temporal_schema}.#{regions}")).to be(true)
      expect(adapter.foreign_key_exists?("#{temporal_schema}.#{countries}", to_table: regions)).to be(true)

      adapter.add_foreign_key "#{temporal_schema}.#{countries}", "#{temporal_schema}.#{regions}", if_not_exists: true

      expect(adapter.foreign_keys(countries).count { |fk| fk.to_table == regions }).to eq 1
    end
  end

  describe 'conversion of a plain table with foreign keys to temporal' do
    let(:districts) { 'fk_districts' }

    before do
      adapter.create_table districts do |t|
        t.string :name
        t.references :fk_region, index: false
      end

      adapter.add_foreign_key districts, regions
    end

    after { adapter.drop_table districts }

    it 'keeps the foreign keys on the table' do
      adapter.change_table districts, temporal: true

      expect(districts).to have_temporal_foreign_key(regions)
      expect(districts).not_to have_foreign_key(regions, to_schema: temporal_schema)
      expect(adapter.foreign_key_exists?(districts, regions)).to be(true)
    end

    it 'keeps enforcing referential integrity on the public view' do
      adapter.change_table districts, temporal: true

      expect do
        adapter.execute "INSERT INTO #{districts} (name, fk_region_id) VALUES ('foo', 0)"
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'keeps the foreign keys when converted back to plain' do
      adapter.change_table districts, temporal: true
      adapter.change_table districts, temporal: false

      expect(districts).to have_foreign_key(regions, to_schema: temporal_schema)
      expect(adapter.foreign_key_exists?(districts, regions)).to be(true)
    end
  end

  describe 'referential integrity' do
    before { adapter.add_foreign_key countries, regions, on_delete: :cascade }

    it 'cascades deletes of current data while preserving the history' do
      adapter.execute "INSERT INTO #{regions} (name) VALUES ('region')"
      region_id = adapter.select_value "SELECT id FROM #{regions}"

      adapter.execute "INSERT INTO #{countries} (name, fk_region_id) VALUES ('country', #{region_id})"
      adapter.execute "DELETE FROM #{regions} WHERE id = #{region_id}"

      expect(adapter.select_value("SELECT COUNT(*) FROM #{countries}")).to eq 0
      expect(adapter.select_value("SELECT COUNT(*) FROM history.#{countries}")).to eq 1
    end
  end
end
