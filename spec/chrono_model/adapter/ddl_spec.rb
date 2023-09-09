# frozen_string_literal: true

require 'spec_helper'
require 'support/adapter/structure'

RSpec.describe ChronoModel::Adapter do
  include ChronoTest::Adapter::Helpers
  include ChronoTest::Adapter::Structure

  let(:current) { [ChronoModel::Adapter::TEMPORAL_SCHEMA, table].join('.') }
  let(:history) { [ChronoModel::Adapter::HISTORY_SCHEMA,  table].join('.') }

  def count(table)
    adapter.select_value("SELECT COUNT(*) FROM ONLY #{table}").to_i
  end

  def ids(table)
    adapter.select_values("SELECT id FROM ONLY #{table} ORDER BY id")
  end

  describe 'INSERT multiple values' do
    before :all do
      adapter.create_table table, temporal: true, &columns
    end

    after :all do
      adapter.drop_table table
    end

    context 'when succeeding' do
      let(:insert) do
        adapter.execute <<-SQL.squish
          INSERT INTO #{table} (test, foo) VALUES
            ('test1', 1),
            ('test2', 2);
        SQL
      end

      it { expect { insert }.not_to raise_error }
      it { expect(count(current)).to eq 2 }
      it { expect(count(history)).to eq 2 }
    end

    context 'when failing' do
      let(:insert) do
        adapter.execute <<-SQL.squish
          INSERT INTO #{table} (test, foo) VALUES
            ('test3', 3),
            (NULL,    0);
        SQL
      end

      it { expect { insert }.to raise_error(ActiveRecord::StatementInvalid) }
      it { expect(count(current)).to eq 2 } # Because the previous
      it { expect(count(history)).to eq 2 } # records are preserved
    end

    context 'when inserting after a failure' do
      let(:insert) do
        adapter.execute <<-SQL.squish
          INSERT INTO #{table} (test, foo) VALUES
            ('test4', 3),
            ('test5', 4);
        SQL
      end

      it { expect { insert }.not_to raise_error }

      it { expect(count(current)).to eq 4 }
      it { expect(count(history)).to eq 4 }

      it { expect(ids(current)).to eq ids(history) }
    end
  end

  describe 'INSERT on NOT NULL columns but with a DEFAULT value' do
    before :all do
      adapter.create_table table, temporal: true, &columns
    end

    after :all do
      adapter.drop_table table
    end

    let(:insert) do
      adapter.execute <<-SQL.squish
        INSERT INTO #{table} DEFAULT VALUES
      SQL
    end

    let(:select) do
      adapter.select_values <<-SQL.squish
        SELECT test FROM #{table}
      SQL
    end

    it { expect { insert }.not_to raise_error }

    it {
      insert
      expect(select.uniq).to eq ['default-value']
    }
  end

  describe 'INSERT with string IDs' do
    before :all do
      adapter.create_table table, temporal: true, id: :string, &columns
    end

    after :all do
      adapter.drop_table table
    end

    let(:insert) do
      adapter.execute <<-SQL.squish
        INSERT INTO #{table} (test, id) VALUES ('test1', 'hello');
      SQL
    end

    it { expect { insert }.not_to raise_error }
    it { expect(count(current)).to eq 1 }
    it { expect(count(history)).to eq 1 }
  end

  describe 'redundant UPDATEs' do
    before :all do
      adapter.create_table table, temporal: true, &columns

      adapter.execute <<-SQL.squish
        INSERT INTO #{table} (test, foo) VALUES ('test1', 1);
      SQL

      adapter.execute <<-SQL.squish
        UPDATE #{table} SET test = 'test2';
      SQL

      adapter.execute <<-SQL.squish
        UPDATE #{table} SET test = 'test2';
      SQL
    end

    after :all do
      adapter.drop_table table
    end

    it { expect(count(current)).to eq 1 }
    it { expect(count(history)).to eq 2 }
  end

  describe 'UPDATEs on non-journaled fields' do
    before :all do
      adapter.create_table table, temporal: true do |t|
        t.string 'test'
        t.timestamps null: false
      end

      adapter.execute <<-SQL.squish
        INSERT INTO #{table} (test, created_at, updated_at) VALUES ('test', now(), now());
      SQL

      adapter.execute <<-SQL.squish
        UPDATE #{table} SET test = 'test2', updated_at = now();
      SQL

      2.times do
        adapter.execute <<-SQL.squish # Redundant update with only updated_at change
          UPDATE #{table} SET test = 'test2', updated_at = now();
        SQL

        adapter.execute <<-SQL.squish
          UPDATE #{table} SET updated_at = now();
        SQL
      end
    end

    after :all do
      adapter.drop_table table
    end

    it { expect(count(current)).to eq 1 }
    it { expect(count(history)).to eq 2 }
  end

  context 'with selective journaled fields' do
    describe 'basic behaviour' do
      it 'does not record history when ignored fields change' do
        adapter.create_table table, temporal: true, journal: %w[foo] do |t|
          t.string 'foo'
          t.string 'bar'
        end

        adapter.execute <<-SQL.squish
          INSERT INTO #{table} (foo, bar) VALUES ('test foo', 'test bar');
        SQL

        adapter.execute <<-SQL.squish
          UPDATE #{table} SET foo = 'test foo', bar = 'no history';
        SQL

        2.times do
          adapter.execute <<-SQL.squish
            UPDATE #{table} SET bar = 'really no history';
          SQL
        end

        expect(count(current)).to eq 1
        expect(count(history)).to eq 1

        adapter.drop_table table
      end
    end

    describe 'schema changes' do
      table 'journaled_things'

      before do
        adapter.create_table table, temporal: true, journal: %w[foo] do |t|
          t.string 'foo'
          t.string 'bar'
          t.string 'baz'
        end
      end

      after do
        adapter.drop_table table
      end

      it 'preserves options upon column change' do
        adapter.change_table table, temporal: true, journal: %w[foo bar]

        adapter.execute <<-SQL.squish
          INSERT INTO #{table} (foo, bar) VALUES ('test foo', 'test bar');
        SQL

        expect(count(current)).to eq 1
        expect(count(history)).to eq 1

        adapter.execute <<-SQL.squish
          UPDATE #{table} SET foo = 'test foo', bar = 'chronomodel';
        SQL

        expect(count(current)).to eq 1
        expect(count(history)).to eq 2
      end

      it 'changes option upon table change' do
        adapter.change_table table, temporal: true, journal: %w[bar]

        adapter.execute <<-SQL.squish
          INSERT INTO #{table} (foo, bar) VALUES ('test foo', 'test bar');
          UPDATE #{table} SET foo = 'test foo', bar = 'no history';
        SQL

        expect(count(current)).to eq 1
        expect(count(history)).to eq 1

        adapter.execute <<-SQL.squish
          UPDATE #{table} SET foo = 'test foo again', bar = 'no history';
        SQL

        expect(count(current)).to eq 1
        expect(count(history)).to eq 1
      end
    end
  end
end
