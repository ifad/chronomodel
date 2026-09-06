# frozen_string_literal: true

require 'spec_helper'
require 'support/adapter/structure'

RSpec.describe ChronoModel::Adapter do
  include ChronoTest::Adapter::Structure

  subject { adapter }

  it { is_expected.to be_a(described_class) }

  describe '.adapter_name' do
    subject { adapter.adapter_name }

    it { is_expected.to eq 'PostgreSQL' }
  end

  describe '.chrono_supported?' do
    subject { adapter.chrono_supported? }

    before { allow(adapter).to receive(:postgresql_version).and_return(postgres_version) }

    context 'with Postgres 9.3' do
      let(:postgres_version) { 90_300 }

      it { is_expected.to be true }
    end

    context 'with Postgres 9.0' do
      let(:postgres_version) { 90_000 }

      it { is_expected.to be false }
    end
  end

  describe '.on_schema' do
    subject(:on_schema) { adapter }

    before do
      adapter.execute 'BEGIN'
      5.times { |i| adapter.execute "CREATE SCHEMA test_#{i}" }
    end

    after do
      adapter.execute 'ROLLBACK'
    end

    context 'with default settings' do
      it 'saves the schema at each recursion' do
        expect(on_schema).to be_in_schema(:default)

        adapter.on_schema('test_1') do
          expect(on_schema).to be_in_schema('test_1')
          adapter.on_schema('test_2') do
            expect(on_schema).to be_in_schema('test_2')
            adapter.on_schema('test_3') do
              expect(on_schema).to be_in_schema('test_3')
            end
            expect(on_schema).to be_in_schema('test_2')
          end
          expect(on_schema).to be_in_schema('test_1')
        end

        expect(on_schema).to be_in_schema(:default)
      end

      context 'when errors occur' do
        subject(:on_schema) do
          adapter.on_schema('test_1') do
            adapter.on_schema('test_2') do
              adapter.execute 'ERRORING ON PURPOSE'
            end
          end
        end

        it 'restores the schema after rollback' do
          original_path = adapter.schema_search_path

          expect { on_schema }.to raise_error(ActiveRecord::StatementInvalid)

          adapter.execute 'ROLLBACK'

          expect(adapter.schema_search_path).to eq(original_path)
          expect(adapter).to be_in_schema(original_path)
        end
      end
    end

    context 'with recurse: :ignore' do
      it 'ignores recursive calls' do
        expect(on_schema).to be_in_schema(:default)

        adapter.on_schema('test_1', recurse: :ignore) do
          expect(on_schema).to be_in_schema('test_1')
          adapter.on_schema('test_2',
                            recurse: :ignore) do
            expect(on_schema).to be_in_schema('test_1')
            adapter.on_schema('test_3',
                              recurse: :ignore) do
              expect(on_schema).to be_in_schema('test_1')
            end
          end
        end

        expect(on_schema).to be_in_schema(:default)
      end
    end
  end

  describe '.columns' do
    include_context 'with temporal tables'

    it 'reads defaults and null constraints from the temporal table' do
      column = adapter.columns(table).find { |field| field.name == 'test' }

      expect(column.default).to eq('default-value')
      expect(column.null).to be false
    end
  end

  describe 'bulk schema metadata',
           if: ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.private_method_defined?(:fetch_column_definitions) do
    include_context 'with temporal tables'

    let(:tables) { [table, 'plain_table', "history.#{table}"] }

    before do
      adapter.create_table('plain_table', &columns)
      adapter.add_index('plain_table', :test)
      adapter.add_index(table, :test)
    end

    after { adapter.drop_table('plain_table') }

    it 'reads columns from each table in its appropriate schema' do
      result = adapter.columns(tables).transform_values { |fields| fields.index_by(&:name) }

      tables.each do |name|
        expect(result.fetch(name).fetch('test').default).to eq('default-value')
        expect(result.fetch(name).fetch('test').null).to be false
      end
      expect(result.fetch("history.#{table}")).to have_key('hid')
      expect(result.fetch(table)).not_to have_key('hid')
    end

    it 'reads primary keys from temporal, plain and history tables' do
      expect(adapter.primary_keys(tables)).to eq(
        table => ['id'], 'plain_table' => ['id'], "history.#{table}" => ['hid']
      )
    end

    it 'returns the same indexes as individual lookups' do
      expected = tables.index_with { |name| adapter.indexes(name).map(&:name) }

      expect(adapter.indexes(tables).transform_values { |indexes| indexes.map(&:name) }).to eq(expected)
    end

    it 'returns empty hashes for empty table lists' do
      expect(adapter.columns([])).to eq({})
      expect(adapter.primary_keys([])).to eq({})
      expect(adapter.indexes([])).to eq({})
    end
  end

  describe '.is_chrono?' do
    subject(:is_chrono?) { adapter.is_chrono?(table) }

    context 'with temporal tables' do
      include_context 'with temporal tables'

      it { is_expected.to be true }
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      it { is_expected.to be false }
    end

    context 'when schemas are not there yet' do
      before do
        adapter.execute 'BEGIN'
        adapter.execute 'DROP SCHEMA temporal CASCADE'
        adapter.execute 'DROP SCHEMA history CASCADE'
        adapter.execute 'CREATE TABLE test_table (id integer)'
      end

      after do
        adapter.execute 'ROLLBACK'
      end

      it 'does not raise errors' do
        expect do
          is_chrono?
        end.not_to raise_error
      end

      it { is_expected.to be false }
    end
  end
end
