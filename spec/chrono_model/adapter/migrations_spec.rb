# frozen_string_literal: true

require 'spec_helper'
require 'support/adapter/structure'

# For the structure of these tables, please see spec/support/adabters/structure.rb.

RSpec.shared_examples_for 'temporal table' do
  it { expect(adapter.is_chrono?(subject)).to be(true) }

  it { is_expected.not_to have_public_backing }

  it { is_expected.to have_temporal_backing }
  it { is_expected.to have_history_backing }
  it { is_expected.to have_history_extra_columns }
  it { is_expected.to have_history_functions }
  it { is_expected.to have_public_interface }

  it { is_expected.to have_columns(columns) }
  it { is_expected.to have_temporal_columns(columns) }
  it { is_expected.to have_history_columns(columns) }
end

RSpec.shared_examples_for 'plain table' do
  it { expect(adapter.is_chrono?(subject)).to be(false) }

  it { is_expected.to have_public_backing }

  it { is_expected.not_to have_temporal_backing }
  it { is_expected.not_to have_history_backing }
  it { is_expected.not_to have_history_functions }
  it { is_expected.not_to have_public_interface }

  it { is_expected.to have_columns(columns) }
end

RSpec.describe ChronoModel::Adapter do
  include ChronoTest::Adapter::Structure

  describe '.create_table' do
    context 'with temporal tables' do
      include_context 'with temporal tables'
      it_behaves_like 'temporal table'

      context 'when defining indexes in the table block' do
        let(:columns) do
          proc do |t|
            t.references :activity
            t.belongs_to :owner, index: true
            t.references :subject, polymorphic: true
            t.references :unindexed, index: false
            t.references :unique, index: { unique: true, name: 'unique_reference_index', where: 'unique_id IS NOT NULL', order: :desc }
            t.string :code, index: { opclass: :varchar_pattern_ops }
            t.index %i[activity_id owner_id], name: 'compound_reference_index'
          end
        end

        it 'creates reference indexes in both schemas' do
          expect(table).to have_temporal_index 'index_test_table_on_activity_id', %w[activity_id]
          expect(table).to have_history_index 'index_test_table_on_activity_id', %w[activity_id]
        end

        it 'creates belongs_to indexes in both schemas' do
          expect(table).to have_temporal_index 'index_test_table_on_owner_id', %w[owner_id]
          expect(table).to have_history_index 'index_test_table_on_owner_id', %w[owner_id]
        end

        it 'preserves polymorphic index column order in both schemas' do
          %w[temporal history].each do |schema|
            indexes = adapter.on_schema(schema) { adapter.indexes(table) }

            expect(indexes).to include(have_attributes(columns: %w[subject_type subject_id]))
          end
        end

        it 'does not create indexes when disabled' do
          expect(table).not_to have_temporal_index 'index_test_table_on_unindexed_id', %w[unindexed_id]
          expect(table).not_to have_history_index 'index_test_table_on_unindexed_id', %w[unindexed_id]
        end

        it 'preserves reference index options except uniqueness in history' do
          temporal_index = adapter.indexes(table).find { |index| index.name == 'unique_reference_index' }
          history_indexes = adapter.on_schema('history') { adapter.indexes(table) }

          expect(temporal_index).to have_attributes(
            unique: true, columns: %w[unique_id], where: '(unique_id IS NOT NULL)', orders: :desc
          )
          expect(history_indexes).to include(
            have_attributes(name: temporal_index.name, columns: temporal_index.columns, unique: false,
                            where: temporal_index.where, orders: temporal_index.orders)
          )
        end

        it 'preserves inline column index options in both schemas' do
          %w[temporal history].each do |schema|
            indexes = adapter.on_schema(schema) { adapter.indexes(table) }

            expect(indexes).to include(
              have_attributes(name: 'index_test_table_on_code', columns: %w[code], opclasses: :varchar_pattern_ops)
            )
          end
        end

        it 'creates explicit composite indexes in both schemas' do
          expect(table).to have_temporal_index 'compound_reference_index', %w[activity_id owner_id]
          expect(table).to have_history_index 'compound_reference_index', %w[activity_id owner_id]
        end

        it 'recreates indexes when forcing table creation' do
          adapter.create_table table, temporal: true, force: true, &columns

          expect(table).to have_temporal_index 'index_test_table_on_activity_id', %w[activity_id]
          expect(table).to have_history_index 'index_test_table_on_activity_id', %w[activity_id]
        end
      end

      # FIXME: Creating a temporal table without a block generates invalid trigger SQL.
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      it_behaves_like 'plain table'

      it 'creates reference indexes only in the public schema' do
        adapter.create_table table, force: true do |t|
          t.references :activity
        end

        expect(table).to have_index 'index_test_table_on_activity_id', %w[activity_id]
        expect(table).not_to have_temporal_index 'index_test_table_on_activity_id', %w[activity_id]
        expect(table).not_to have_history_index 'index_test_table_on_activity_id', %w[activity_id]
      end
    end
  end

  describe '.rename_table' do
    subject { renamed }

    let(:renamed) { 'foo_table' }

    context 'with temporal tables' do
      before do
        adapter.create_table table, temporal: true, &columns
        adapter.add_index table, :test
        adapter.add_index table, %i[foo bar]

        adapter.rename_table table, renamed
      end

      after { adapter.drop_table(renamed) }

      it_behaves_like 'temporal table'

      it 'renames indexes' do
        new_index_names = adapter.indexes(renamed).map(&:name)
        expected_index_names = [[:test], %i[foo bar]].map do |idx_cols|
          "index_#{renamed}_on_#{idx_cols.join('_and_')}"
        end
        expect(new_index_names.to_set).to eq expected_index_names.to_set
      end
    end

    context 'with plain tables' do
      before do
        adapter.create_table table, temporal: false, &columns

        adapter.rename_table table, renamed
      end

      after { adapter.drop_table(renamed) }

      it_behaves_like 'plain table'
    end
  end

  describe '.change_table' do
    context 'with temporal tables' do
      include_context 'with temporal tables'

      context 'when explicitly requesting temporal: false' do
        before do
          adapter.change_table table, temporal: false
        end

        it_behaves_like 'plain table'
      end

      context 'when adding a column without specifying temporal: true' do
        before do
          adapter.change_table table do |t|
            t.integer :new_column
          end
        end

        it_behaves_like 'temporal table'

        it { is_expected.to have_columns([%w[new_column integer]]) }
        it { is_expected.to have_temporal_columns([%w[new_column integer]]) }
        it { is_expected.to have_history_columns([%w[new_column integer]]) }
      end
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      context 'when adding a column' do
        before do
          adapter.change_table table do |t|
            t.string :frupper
          end
        end

        it_behaves_like 'plain table'

        it { is_expected.to have_columns([['frupper', 'character varying']]) }
      end

      context 'when setting temporal: true' do
        before do
          adapter.add_index table, :foo
          adapter.add_index table, :bar, unique: true
          adapter.add_index table, '(lower(baz))'
          adapter.add_index table, '(lower(baz) || upper(baz))'

          adapter.change_table table, temporal: true
        end

        let(:temporal_indexes) do
          adapter.indexes(table)
        end

        let(:history_indexes) do
          adapter.on_schema(ChronoModel::Adapter::HISTORY_SCHEMA) do
            adapter.indexes(table)
          end
        end

        it_behaves_like 'temporal table'

        it 'copies plain index to history' do
          expect(history_indexes.find { |i| i.columns == ['foo'] }).to be_present
        end

        it 'copies unique index to history without uniqueness constraint' do
          expect(history_indexes.find { |i| i.columns == ['bar'] && i.unique == false }).to be_present
        end

        it 'copies also computed indexes' do
          indexes = %W[
            index_#{table}_on_bar
            index_#{table}_on_foo
            index_#{table}_on_lower_baz
            index_#{table}_on_lower_baz_upper_baz
          ]

          expect(temporal_indexes.map(&:name).sort).to eq(indexes)

          expect(indexes - history_indexes.map(&:name).sort).to be_empty
        end
      end
    end

    # https://github.com/ifad/chronomodel/issues/91
    context 'with a table using a sequence not owned by a column' do
      before do
        adapter.execute 'create sequence temporal.foobar owned by none'
        adapter.execute "create table #{table} (id integer primary key default nextval('temporal.foobar'::regclass), label character varying)"
      end

      after do
        adapter.execute "drop table if exists #{table}"
        adapter.execute 'drop sequence temporal.foobar'
      end

      it { is_expected.to have_columns([%w[id integer], ['label', 'character varying']]) }

      context 'when moving to temporal' do
        before do
          adapter.change_table table, temporal: true
        end

        after do
          adapter.drop_table table
        end

        it { is_expected.to have_columns([%w[id integer], ['label', 'character varying']]) }
        it { is_expected.to have_temporal_columns([%w[id integer], ['label', 'character varying']]) }
        it { is_expected.to have_history_columns([%w[id integer], ['label', 'character varying']]) }

        it { is_expected.to have_function_source("chronomodel_#{table}_insert", /NEW\.id := nextval\('temporal.foobar'\)/) }
      end
    end
  end

  describe '.drop_table' do
    context 'with temporal tables' do
      before do
        adapter.create_table table, temporal: true, &columns

        adapter.drop_table table
      end

      it { is_expected.not_to have_public_backing }
      it { is_expected.not_to have_temporal_backing }
      it { is_expected.not_to have_history_backing }
      it { is_expected.not_to have_history_functions }
      it { is_expected.not_to have_public_interface }
    end

    context 'with plain tables' do
      before do
        adapter.create_table table, temporal: false, &columns

        adapter.drop_table table, temporal: false
      end

      it { is_expected.not_to have_public_backing }
      it { is_expected.not_to have_public_interface }
    end
  end

  describe '.add_index' do
    context 'with temporal tables' do
      include_context 'with temporal tables'

      before do
        adapter.add_index table, %i[foo bar], name: 'foobar_index'
        adapter.add_index table, [:test], name: 'test_index'
        adapter.add_index table, :baz
      end

      it { is_expected.to have_temporal_index 'foobar_index', %w[foo bar] }
      it { is_expected.to have_history_index  'foobar_index', %w[foo bar] }
      it { is_expected.to have_temporal_index 'test_index',   %w[test] }
      it { is_expected.to have_history_index  'test_index',   %w[test] }
      it { is_expected.to have_temporal_index 'index_test_table_on_baz', %w[baz] }
      it { is_expected.to have_history_index  'index_test_table_on_baz', %w[baz] }

      it { is_expected.not_to have_index 'foobar_index', %w[foo bar] }
      it { is_expected.not_to have_index 'test_index',   %w[test] }
      it { is_expected.not_to have_index 'index_test_table_on_baz', %w[baz] }
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      before do
        adapter.add_index table, %i[foo bar], name: 'foobar_index'
        adapter.add_index table, [:test], name: 'test_index'
        adapter.add_index table, :baz
      end

      it { is_expected.not_to have_temporal_index 'foobar_index', %w[foo bar] }
      it { is_expected.not_to have_history_index  'foobar_index', %w[foo bar] }
      it { is_expected.not_to have_temporal_index 'test_index',   %w[test] }
      it { is_expected.not_to have_history_index  'test_index',   %w[test] }
      it { is_expected.not_to have_temporal_index 'index_test_table_on_baz', %w[baz] }
      it { is_expected.not_to have_history_index  'index_test_table_on_baz', %w[baz] }

      it { is_expected.to have_index 'foobar_index', %w[foo bar] }
      it { is_expected.to have_index 'test_index',   %w[test] }
      it { is_expected.to have_index 'index_test_table_on_baz', %w[baz] }
    end
  end

  describe '.remove_index' do
    context 'with temporal tables' do
      include_context 'with temporal tables'

      before do
        adapter.add_index table, %i[foo bar], name: 'foobar_index'
        adapter.add_index table, [:test], name: 'test_index'
        adapter.add_index table, :baz

        adapter.remove_index table, name: 'test_index'
        adapter.remove_index table, :baz
      end

      it { is_expected.not_to have_temporal_index 'test_index', %w[test] }
      it { is_expected.not_to have_history_index  'test_index', %w[test] }
      it { is_expected.not_to have_index          'test_index', %w[test] }

      it { is_expected.not_to have_temporal_index 'index_test_table_on_baz', %w[baz] }
      it { is_expected.not_to have_history_index  'index_test_table_on_baz', %w[baz] }
      it { is_expected.not_to have_index          'index_test_table_on_baz', %w[baz] }
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      before do
        adapter.add_index table, %i[foo bar], name: 'foobar_index'
        adapter.add_index table, [:test], name: 'test_index'
        adapter.add_index table, :baz

        adapter.remove_index table, name: 'test_index'
        adapter.remove_index table, :baz
      end

      it { is_expected.not_to have_temporal_index 'test_index', %w[test] }
      it { is_expected.not_to have_history_index  'test_index', %w[test] }
      it { is_expected.not_to have_index          'test_index', %w[test] }

      it { is_expected.not_to have_temporal_index 'index_test_table_on_baz', %w[baz] }
      it { is_expected.not_to have_history_index  'index_test_table_on_baz', %w[baz] }
      it { is_expected.not_to have_index          'index_test_table_on_baz', %w[baz] }
    end
  end

  describe '.add_column' do
    let(:extra_columns) { [%w[foobarbaz integer]] }

    context 'with temporal tables' do
      include_context 'with temporal tables'

      context 'with options' do
        before do
          adapter.add_column table, :foobarbaz, :integer, default: 0
        end

        it { is_expected.to have_columns(extra_columns) }
        it { is_expected.to have_temporal_columns(extra_columns) }
        it { is_expected.to have_history_columns(extra_columns) }
      end

      context 'without options' do
        before do
          adapter.add_column table, :foobarbaz, :integer
        end

        it { is_expected.to have_columns(extra_columns) }
        it { is_expected.to have_temporal_columns(extra_columns) }
        it { is_expected.to have_history_columns(extra_columns) }
      end
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      context 'with options' do
        before do
          adapter.add_column table, :foobarbaz, :integer, default: 0
        end

        it { is_expected.to have_columns(extra_columns) }
      end

      context 'without options' do
        before do
          adapter.add_column table, :foobarbaz, :integer
        end

        it { is_expected.to have_columns(extra_columns) }
      end
    end
  end

  describe '.remove_column' do
    let(:resulting_columns) { columns.reject { |c, _| c == 'foo' } }

    context 'with temporal tables' do
      include_context 'with temporal tables'

      context 'without options' do
        before do
          adapter.remove_column table, :foo
        end

        it { is_expected.not_to have_columns([%w[foo integer]]) }
        it { is_expected.not_to have_temporal_columns([%w[foo integer]]) }
        it { is_expected.not_to have_history_columns([%w[foo integer]]) }
      end

      context 'with options' do
        before do
          adapter.remove_column table, :foo, :integer, default: 0
        end

        it { is_expected.to have_columns(resulting_columns) }
        it { is_expected.to have_temporal_columns(resulting_columns) }
        it { is_expected.to have_history_columns(resulting_columns) }

        it { is_expected.not_to have_columns([%w[foo integer]]) }
        it { is_expected.not_to have_temporal_columns([%w[foo integer]]) }
        it { is_expected.not_to have_history_columns([%w[foo integer]]) }
      end
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      context 'with options' do
        before do
          adapter.remove_column table, :foo, :integer, default: 0
        end

        it { is_expected.to have_columns(resulting_columns) }
        it { is_expected.not_to have_columns([%w[foo integer]]) }
      end

      context 'without options' do
        before do
          adapter.remove_column table, :foo
        end

        it { is_expected.not_to have_columns([%w[foo integer]]) }
      end
    end
  end

  describe '.rename_column' do
    context 'with temporal tables' do
      include_context 'with temporal tables'

      before do
        adapter.rename_column table, :foo, :taratapiatapioca
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.not_to have_temporal_columns([%w[foo integer]]) }
      it { is_expected.not_to have_history_columns([%w[foo integer]]) }

      it { is_expected.to have_columns([%w[taratapiatapioca integer]]) }
      it { is_expected.to have_temporal_columns([%w[taratapiatapioca integer]]) }
      it { is_expected.to have_history_columns([%w[taratapiatapioca integer]]) }
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      before do
        adapter.rename_column table, :foo, :taratapiatapioca
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.to have_columns([%w[taratapiatapioca integer]]) }
    end
  end

  describe '.change_column' do
    context 'with temporal tables' do
      include_context 'with temporal tables'

      context 'with options' do
        before do
          adapter.change_column table, :foo, :float, default: 0
        end

        it { is_expected.not_to have_columns([%w[foo integer]]) }
      end

      context 'without options' do
        before do
          adapter.change_column table, :foo, :float
        end

        it { is_expected.not_to have_columns([%w[foo integer]]) }
        it { is_expected.not_to have_temporal_columns([%w[foo integer]]) }
        it { is_expected.not_to have_history_columns([%w[foo integer]]) }

        it { is_expected.to have_columns([['foo', 'double precision']]) }
        it { is_expected.to have_temporal_columns([['foo', 'double precision']]) }
        it { is_expected.to have_history_columns([['foo', 'double precision']]) }
      end
    end

    context 'with plain tables' do
      include_context 'with plain tables'

      before do
        adapter.change_column table, :foo, :float
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.to have_columns([['foo', 'double precision']]) }
    end
  end
end
