# frozen_string_literal: true

require 'active_support/core_ext/string/strip'
require 'multi_json'

module ChronoModel
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    # DDL (Data Definition Language) operations for temporal table management.
    #
    # This module provides the core functionality for creating and managing
    # temporal table structures, including public views, history tables,
    # and INSTEAD OF triggers that implement the temporal behavior.
    module DDL
      private

      # Creates the public view and its INSTEAD OF triggers for a temporal table.
      #
      # The public view provides the interface that applications interact with,
      # while the triggers handle the temporal logic for INSERT, UPDATE, and DELETE operations.
      #
      # @param table [String] the table name
      # @param options [Hash] temporal table options
      # @option options [Array<String>] :journal columns to include in history tracking
      # @option options [Array<String>] :no_journal columns to exclude from history tracking
      # @option options [Boolean] :full_journal whether to track all columns in history
      # @return [void]
      # @api private
      def chrono_public_view_ddl(table, options = nil)
        pk      = primary_key(table)
        current = "#{TEMPORAL_SCHEMA}.#{table}"
        history = "#{HISTORY_SCHEMA}.#{table}"

        options ||= chrono_metadata_for(table)

        # SELECT - return only current data
        #
        execute "DROP VIEW #{table}" if data_source_exists? table
        execute "CREATE VIEW #{table} AS SELECT * FROM ONLY #{current}"

        chrono_metadata_set(table, options.merge(chronomodel: VERSION))

        # Set default values on the view (closes #12)
        #
        columns(table).each do |column|
          default =
            if column.default.nil?
              column.default_function
            else
              quote(column.default)
            end

          next if column.name == pk || default.nil?

          execute "ALTER VIEW #{table} ALTER COLUMN #{quote_column_name(column.name)} SET DEFAULT #{default}"
        end

        columns = self.columns(table).map { |c| quote_column_name(c.name) }
        columns.delete(quote_column_name(pk))

        fields = columns.join(', ')
        values = columns.map { |c| "NEW.#{c}" }.join(', ')

        chrono_create_INSERT_trigger(table, pk, current, history, fields, values)
        chrono_create_UPDATE_trigger(table, pk, current, history, fields, values, options, columns)
        chrono_create_DELETE_trigger(table, pk, current, history)
      end

      # Creates the history table in the history schema.
      #
      # The history table inherits from the temporal table and adds temporal-specific
      # columns: hid (history ID), validity (time range), and recorded_at (audit timestamp).
      #
      # @param table [String] the table name
      # @return [void]
      # @api private
      def chrono_history_table_ddl(table)
        parent = "#{TEMPORAL_SCHEMA}.#{table}"
        p_pkey = primary_key(parent)

        execute <<~SQL.squish
          CREATE TABLE #{table} (
            hid         BIGSERIAL PRIMARY KEY,
            validity    tsrange NOT NULL,
            recorded_at timestamp NOT NULL DEFAULT timezone('UTC', now())
          ) INHERITS (#{parent})
        SQL

        add_history_validity_constraint(table, p_pkey)

        chrono_create_history_indexes_for(table, p_pkey)
      end

      # Adds a validity constraint to the history table.
      #
      # @param table [String] the table name
      # @param pkey [String] the primary key column name
      # @return [void]
      # @api private
      def add_history_validity_constraint(table, pkey)
        add_timeline_consistency_constraint(table, :validity, id: pkey, on_current_schema: true)
      end

      # Removes the validity constraint from the history table.
      #
      # @param table [String] the table name
      # @param options [Hash] constraint removal options
      # @return [void]
      # @api private
      def remove_history_validity_constraint(table, options = {})
        remove_timeline_consistency_constraint(table, options.merge(on_current_schema: true))
      end

      # Creates the INSERT trigger function and trigger for a temporal table.
      #
      # The INSERT trigger inserts data both in the temporal table and in the history table.
      # The serial sequence is invoked manually only if the PK is NULL, to allow setting
      # the PK to a specific value (useful for migration scenarios).
      #
      # @param table [String] the table name
      # @param pk [String] the primary key column name
      # @param current [String] the temporal schema table name
      # @param history [String] the history schema table name
      # @param fields [String] comma-separated list of column names
      # @param values [String] comma-separated list of NEW.column references
      # @return [void]
      # @api private
      def chrono_create_INSERT_trigger(table, pk, current, history, fields, values)
        execute <<-SQL.strip_heredoc # rubocop:disable Rails/SquishedSQLHeredocs,Rails/StripHeredoc
            CREATE OR REPLACE FUNCTION chronomodel_#{table}_insert() RETURNS TRIGGER AS $$
                BEGIN
                    #{insert_sequence_sql(pk, current)} INTO #{current} (#{pk}, #{fields})
                    VALUES (NEW.#{pk}, #{values});

                    INSERT INTO #{history} (#{pk}, #{fields}, validity)
                    VALUES (NEW.#{pk}, #{values}, tsrange(timezone('UTC', now()), NULL));

                    RETURN NEW;
                END;

            $$ LANGUAGE plpgsql;

            DROP TRIGGER IF EXISTS chronomodel_insert ON #{table};

            CREATE TRIGGER chronomodel_insert INSTEAD OF INSERT ON #{table}
                FOR EACH ROW EXECUTE PROCEDURE chronomodel_#{table}_insert();
        SQL
      end

      # Creates the UPDATE trigger function and trigger for a temporal table.
      #
      # The UPDATE trigger sets the last history entry validity to now, saves the current
      # data in a new history entry and updates the temporal table with the new data.
      #
      # If there are no changes, this trigger suppresses redundant updates.
      # If a row in the history with the current ID and current timestamp already exists,
      # it updates that row with new data (squashing behavior).
      #
      # @param table [String] the table name
      # @param pk [String] the primary key column name
      # @param current [String] the temporal schema table name
      # @param history [String] the history schema table name
      # @param fields [String] comma-separated list of column names
      # @param values [String] comma-separated list of NEW.column references
      # @param options [Hash] temporal table options
      # @param columns [Array<String>] list of quoted column names
      # @return [void]
      # @api private
      def chrono_create_UPDATE_trigger(table, pk, current, history, fields, values, options, columns)
        # Columns to be journaled. By default everything except updated_at (GH #7)
        #
        journal =
          if options[:journal]
            options[:journal].map { |col| quote_column_name(col) }

          elsif options[:no_journal]
            columns - options[:no_journal].map { |col| quote_column_name(col) }

          elsif options[:full_journal]
            columns

          else
            columns - [quote_column_name('updated_at')]
          end

        journal &= columns

        execute <<-SQL.strip_heredoc # rubocop:disable Rails/SquishedSQLHeredocs,Rails/StripHeredoc
            CREATE OR REPLACE FUNCTION chronomodel_#{table}_update() RETURNS TRIGGER AS $$
                DECLARE _now timestamp;
                DECLARE _hid integer;
                DECLARE _old record;
                DECLARE _new record;
                BEGIN
                    IF OLD IS NOT DISTINCT FROM NEW THEN
                        RETURN NULL;
                    END IF;

                    _old := row(#{journal.map { |c| "OLD.#{c}" }.join(', ')});
                    _new := row(#{journal.map { |c| "NEW.#{c}" }.join(', ')});

                    IF _old IS NOT DISTINCT FROM _new THEN
                        UPDATE ONLY #{current} SET (#{fields}) = (#{values}) WHERE #{pk} = OLD.#{pk};
                        RETURN NEW;
                    END IF;

                    _now := timezone('UTC', now());
                    _hid := NULL;

                    #{"SELECT hid INTO _hid FROM #{history} WHERE #{pk} = OLD.#{pk} AND lower(validity) = _now;" unless ENV['CHRONOMODEL_NO_SQUASH']}

                    IF _hid IS NOT NULL THEN
                        UPDATE #{history} SET (#{fields}) = (#{values}) WHERE hid = _hid;
                    ELSE
                        UPDATE #{history} SET validity = tsrange(lower(validity), _now)
                        WHERE #{pk} = OLD.#{pk} AND upper_inf(validity);

                        INSERT INTO #{history} (#{pk}, #{fields}, validity)
                            VALUES (OLD.#{pk}, #{values}, tsrange(_now, NULL));
                    END IF;

                    UPDATE ONLY #{current} SET (#{fields}) = (#{values}) WHERE #{pk} = OLD.#{pk};

                    RETURN NEW;
                END;

            $$ LANGUAGE plpgsql;

            DROP TRIGGER IF EXISTS chronomodel_update ON #{table};

            CREATE TRIGGER chronomodel_update INSTEAD OF UPDATE ON #{table}
                FOR EACH ROW EXECUTE PROCEDURE chronomodel_#{table}_update();
        SQL
      end

      # Creates the DELETE trigger function and trigger for a temporal table.
      #
      # The DELETE trigger saves the current data in the history and eventually deletes
      # the data from the temporal table. The first DELETE is required to remove history
      # for records INSERTed and DELETEd in the same transaction.
      #
      # @param table [String] the table name
      # @param pk [String] the primary key column name
      # @param current [String] the temporal schema table name
      # @param history [String] the history schema table name
      # @return [void]
      # @api private
      def chrono_create_DELETE_trigger(table, pk, current, history)
        execute <<-SQL.strip_heredoc # rubocop:disable Rails/SquishedSQLHeredocs,Rails/StripHeredoc
            CREATE OR REPLACE FUNCTION chronomodel_#{table}_delete() RETURNS TRIGGER AS $$
                DECLARE _now timestamp;
                BEGIN
                    _now := timezone('UTC', now());

                    DELETE FROM #{history}
                    WHERE #{pk} = old.#{pk} AND validity = tsrange(_now, NULL);

                    UPDATE #{history} SET validity = tsrange(lower(validity), _now)
                    WHERE #{pk} = old.#{pk} AND upper_inf(validity);

                    DELETE FROM ONLY #{current}
                    WHERE #{pk} = old.#{pk};

                    RETURN OLD;
                END;

            $$ LANGUAGE plpgsql;

            DROP TRIGGER IF EXISTS chronomodel_delete ON #{table};

            CREATE TRIGGER chronomodel_delete INSTEAD OF DELETE ON #{table}
                FOR EACH ROW EXECUTE PROCEDURE chronomodel_#{table}_delete();
        SQL
      end

      # Drops trigger functions for a temporal table.
      #
      # @param table_name [String] the table name
      # @return [void]
      # @api private
      def chrono_drop_trigger_functions_for(table_name)
        %w[insert update delete].each do |func|
          execute "DROP FUNCTION IF EXISTS chronomodel_#{table_name}_#{func}()"
        end
      end

      # Generates SQL for handling primary key sequences in INSERT triggers.
      #
      # @param pk [String] the primary key column name
      # @param current [String] the temporal schema table name
      # @return [String] SQL fragment for sequence handling
      # @api private
      def insert_sequence_sql(pk, current)
        seq = pk_and_sequence_for(current)
        return 'INSERT' if seq.blank?

        <<-SQL.strip # rubocop:disable Rails/SquishedSQLHeredocs
                    IF NEW.#{pk} IS NULL THEN
                        NEW.#{pk} := nextval('#{seq.last}');
                    END IF;

                    INSERT
        SQL
      end
    end
  end
end
