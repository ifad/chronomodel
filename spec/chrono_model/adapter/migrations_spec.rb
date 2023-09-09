require 'spec_helper'
require 'support/adapter/structure'

# For the structure of these tables, please see spec/support/adabters/structure.rb.
#
# rubocop:disable RSpec/ScatteredSetup
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
  include ChronoTest::Adapter::Helpers
  include ChronoTest::Adapter::Structure

  describe '.create_table' do
    with_temporal_table do
      it_behaves_like 'temporal table'
    end

    with_plain_table do
      it_behaves_like 'plain table'
    end
  end

  describe '.rename_table' do
    renamed = 'foo_table'
    subject { renamed }

    context 'temporal: true' do
      before :all do
        adapter.create_table table, temporal: true, &columns
        adapter.add_index table, :test
        adapter.add_index table, %i[foo bar]

        adapter.rename_table table, renamed
      end

      after(:all) { adapter.drop_table(renamed) }

      it_behaves_like 'temporal table'

      it 'renames indexes' do
        new_index_names = adapter.indexes(renamed).map(&:name)
        expected_index_names = [[:test], %i[foo bar]].map do |idx_cols|
          "index_#{renamed}_on_#{idx_cols.join('_and_')}"
        end
        expect(new_index_names.to_set).to eq expected_index_names.to_set
      end
    end

    context 'temporal: false' do
      before :all do
        adapter.create_table table, temporal: false, &columns

        adapter.rename_table table, renamed
      end

      after(:all) { adapter.drop_table(renamed) }

      it_behaves_like 'plain table'
    end
  end

  describe '.change_table' do
    with_temporal_table do
      before :all do
        adapter.change_table table, temporal: false
      end

      it_behaves_like 'plain table'
    end

    with_plain_table do
      before :all do
        adapter.add_index table, :foo
        adapter.add_index table, :bar, unique: true
        adapter.add_index table, '(lower(baz))'
        adapter.add_index table, '(lower(baz) || upper(baz))'

        adapter.change_table table, temporal: true
      end

      it_behaves_like 'temporal table'

      let(:temporal_indexes) do
        adapter.indexes(table)
      end

      let(:history_indexes) do
        adapter.on_schema(ChronoModel::Adapter::HISTORY_SCHEMA) do
          adapter.indexes(table)
        end
      end

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

    with_plain_table do
      before :all do
        adapter.change_table table do |_t|
          adapter.add_column table, :frupper, :string
        end
      end

      it_behaves_like 'plain table'

      it { is_expected.to have_columns([['frupper', 'character varying']]) }
    end

    # https://github.com/ifad/chronomodel/issues/91
    context 'given a table using a sequence not owned by a column' do
      before :all do
        adapter.execute 'create sequence temporal.foobar owned by none'
        adapter.execute "create table #{table} (id integer primary key default nextval('temporal.foobar'::regclass), label character varying)"
      end

      after :all do
        adapter.execute "drop table if exists #{table}"
        adapter.execute 'drop sequence temporal.foobar'
      end

      it { is_expected.to have_columns([%w[id integer], ['label', 'character varying']]) }

      context 'when moving to temporal' do
        before :all do
          adapter.change_table table, temporal: true
        end

        after :all do
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
      before :all do
        adapter.create_table table, temporal: true, &columns

        adapter.drop_table table
      end

      it { is_expected.not_to have_public_backing }
      it { is_expected.not_to have_temporal_backing }
      it { is_expected.not_to have_history_backing }
      it { is_expected.not_to have_history_functions }
      it { is_expected.not_to have_public_interface }
    end

    context 'without temporal tables' do
      before :all do
        adapter.create_table table, temporal: false, &columns

        adapter.drop_table table, temporal: false
      end

      it { is_expected.not_to have_public_backing }
      it { is_expected.not_to have_public_interface }
    end
  end

  describe '.add_index' do
    with_temporal_table do
      before :all do
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

    with_plain_table do
      before :all do
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
    with_temporal_table do
      before :all do
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

    with_plain_table do
      before :all do
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

    with_temporal_table do
      before :all do
        adapter.add_column table, :foobarbaz, :integer
      end

      it { is_expected.to have_columns(extra_columns) }
      it { is_expected.to have_temporal_columns(extra_columns) }
      it { is_expected.to have_history_columns(extra_columns) }
    end

    with_plain_table do
      before :all do
        adapter.add_column table, :foobarbaz, :integer
      end

      it { is_expected.to have_columns(extra_columns) }
    end

    with_temporal_table do
      before :all do
        adapter.add_column table, :foobarbaz, :integer, default: 0
      end

      it { is_expected.to have_columns(extra_columns) }
      it { is_expected.to have_temporal_columns(extra_columns) }
      it { is_expected.to have_history_columns(extra_columns) }
    end

    with_plain_table do
      before :all do
        adapter.add_column table, :foobarbaz, :integer, default: 0
      end

      it { is_expected.to have_columns(extra_columns) }
    end
  end

  describe '.remove_column' do
    let(:resulting_columns) { columns.reject { |c, _| c == 'foo' } }

    with_temporal_table do
      before :all do
        adapter.remove_column table, :foo, :integer, default: 0
      end

      it { is_expected.to have_columns(resulting_columns) }
      it { is_expected.to have_temporal_columns(resulting_columns) }
      it { is_expected.to have_history_columns(resulting_columns) }

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.not_to have_temporal_columns([%w[foo integer]]) }
      it { is_expected.not_to have_history_columns([%w[foo integer]]) }
    end

    with_plain_table do
      before :all do
        adapter.remove_column table, :foo, :integer, default: 0
      end

      it { is_expected.to have_columns(resulting_columns) }
      it { is_expected.not_to have_columns([%w[foo integer]]) }
    end

    with_temporal_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.not_to have_temporal_columns([%w[foo integer]]) }
      it { is_expected.not_to have_history_columns([%w[foo integer]]) }
    end

    with_plain_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
    end
  end

  describe '.rename_column' do
    with_temporal_table do
      before :all do
        adapter.rename_column table, :foo, :taratapiatapioca
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.not_to have_temporal_columns([%w[foo integer]]) }
      it { is_expected.not_to have_history_columns([%w[foo integer]]) }

      it { is_expected.to have_columns([%w[taratapiatapioca integer]]) }
      it { is_expected.to have_temporal_columns([%w[taratapiatapioca integer]]) }
      it { is_expected.to have_history_columns([%w[taratapiatapioca integer]]) }
    end

    with_plain_table do
      before :all do
        adapter.rename_column table, :foo, :taratapiatapioca
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.to have_columns([%w[taratapiatapioca integer]]) }
    end
  end

  describe '.change_column' do
    with_temporal_table do
      before :all do
        adapter.change_column table, :foo, :float
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.not_to have_temporal_columns([%w[foo integer]]) }
      it { is_expected.not_to have_history_columns([%w[foo integer]]) }

      it { is_expected.to have_columns([['foo', 'double precision']]) }
      it { is_expected.to have_temporal_columns([['foo', 'double precision']]) }
      it { is_expected.to have_history_columns([['foo', 'double precision']]) }

      context 'with options' do
        before :all do
          adapter.change_column table, :foo, :float, default: 0
        end

        it { is_expected.not_to have_columns([%w[foo integer]]) }
      end
    end

    with_plain_table do
      before(:all) do
        adapter.change_column table, :foo, :float
      end

      it { is_expected.not_to have_columns([%w[foo integer]]) }
      it { is_expected.to have_columns([['foo', 'double precision']]) }
    end
  end
end
# rubocop:enable RSpec/ScatteredSetup
