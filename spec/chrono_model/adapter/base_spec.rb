require 'spec_helper'
require 'support/adapter/structure'

RSpec.describe ChronoModel::Adapter do
  include ChronoTest::Adapter::Helpers
  include ChronoTest::Adapter::Structure

  subject { adapter }

  it { is_expected.to be_a_kind_of(ChronoModel::Adapter) }

  context do
    subject { adapter.adapter_name }

    it { is_expected.to eq 'PostgreSQL' }
  end

  context do
    before { expect(adapter).to receive(:postgresql_version).and_return(90_300) }

    it { is_expected.to be_chrono_supported }
  end

  context do
    before { expect(adapter).to receive(:postgresql_version).and_return(90_000) }

    it { is_expected.to_not be_chrono_supported }
  end

  describe '.primary_key' do
    subject { adapter.primary_key(table) }

    assert = proc do
      it { is_expected.to eq 'id' }
    end

    with_temporal_table(&assert)
    with_plain_table(&assert)
  end

  describe '.indexes' do
    subject { adapter.indexes(table) }

    assert = proc do
      before(:all) do
        adapter.add_index table, :foo, name: 'foo_index'
        adapter.add_index table, %i[bar baz], name: 'bar_index'
      end

      it { expect(subject.map(&:name)).to match_array %w[foo_index bar_index] }
      it { expect(subject.map(&:columns)).to match_array [['foo'], %w[bar baz]] }
    end

    with_temporal_table(&assert)
    with_plain_table(&assert)
  end

  describe '.column_definitions' do
    subject { adapter.column_definitions(table).map { |d| d.take(2) } }

    assert = proc do
      it { expect(subject & columns).to eq columns }
      it { is_expected.to include(['id', pk_type]) }
    end

    with_temporal_table(&assert)
    with_plain_table(&assert)
  end

  describe '.on_schema' do
    before(:all) do
      adapter.execute 'BEGIN'
      5.times { |i| adapter.execute "CREATE SCHEMA test_#{i}" }
    end

    after(:all) do
      adapter.execute 'ROLLBACK'
    end

    context 'by default' do
      it 'saves the schema at each recursion' do
        is_expected.to be_in_schema(:default)

        adapter.on_schema('test_1') do
          is_expected.to be_in_schema('test_1')
          adapter.on_schema('test_2') do
            is_expected.to be_in_schema('test_2')
            adapter.on_schema('test_3') do
              is_expected.to be_in_schema('test_3')
            end
            is_expected.to be_in_schema('test_2')
          end
          is_expected.to be_in_schema('test_1')
        end

        is_expected.to be_in_schema(:default)
      end

      context 'when errors occur' do
        subject do
          adapter.on_schema('test_1') do
            adapter.on_schema('test_2') do
              adapter.execute 'BEGIN'
              adapter.execute 'ERRORING ON PURPOSE'
            end
          end
        end

        after do
          adapter.execute 'ROLLBACK'
        end

        it {
          expect { subject }
            .to raise_error(/current transaction is aborted/)
            .and change { adapter.instance_variable_get(:@schema_search_path) }
        }
      end
    end

    context 'with recurse: :ignore' do
      it 'ignores recursive calls' do
        is_expected.to be_in_schema(:default)

        adapter.on_schema('test_1', recurse: :ignore) do
          is_expected.to be_in_schema('test_1')
          adapter.on_schema('test_2',
                            recurse: :ignore) do
            is_expected.to be_in_schema('test_1')
            adapter.on_schema('test_3',
                              recurse: :ignore) do
              is_expected.to be_in_schema('test_1')
            end
          end
        end

        is_expected.to be_in_schema(:default)
      end
    end
  end

  describe '.is_chrono?' do
    with_temporal_table do
      it { expect(adapter.is_chrono?(table)).to be(true) }
    end

    with_plain_table do
      it { expect(adapter.is_chrono?(table)).to be(false) }
    end

    context 'when schemas are not there yet' do
      before(:all) do
        adapter.execute 'BEGIN'
        adapter.execute 'DROP SCHEMA temporal CASCADE'
        adapter.execute 'DROP SCHEMA history CASCADE'
        adapter.execute 'CREATE TABLE test_table (id integer)'
      end

      after(:all) do
        adapter.execute 'ROLLBACK'
      end

      it { expect { adapter.is_chrono?(table) }.to_not raise_error }

      it { expect(adapter.is_chrono?(table)).to be(false) }
    end
  end
end
