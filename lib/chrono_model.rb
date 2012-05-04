require 'chrono_model/version'

require 'active_record'
require 'active_record/connection_adapters/postgresql_adapter'

module ChronoModel
  class Error < ActiveRecord::ActiveRecordError #:nodoc:
  end

  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    # Creates the given table, possibly creating the temporal schema
    # objects if the `:temporal` option is given and set to true.
    #
    def create_table(table_name, options = {})
      # No temporal features requested, skip
      return super unless options[:temporal]

      if options[:id] == false
        raise Error, "Temporal tables require a primary key."
      end

      # Create required schemas
      chrono_create_temporal_schemas!

      transaction do
        super chrono_current_table_for(table_name), options
        chrono_create_history_for(table_name)
        chrono_create_view_for(table_name)
      end
    end

    # If renaming a temporal table, rename the history and view as well.
    #
    def rename_table(name, new_name)
      return super unless is_chrono?(name)

      clear_cache!

      current = chrono_current_table_for(name)
      history = chrono_history_table_for(name)

      [current, history].each do |table|
        seq     = serial_sequence(table, primary_key(table))
        new_seq = seq.sub(name.to_s, new_name.to_s).split('.').last

        execute "ALTER SEQUENCE #{seq} RENAME TO #{new_seq}"
        execute "ALTER TABLE #{table} RENAME TO #{new_name}"
      end
      execute "ALTER VIEW #{chrono_view_for(name)} RENAME TO #{new_name}"
    end

    # If changing a temporal table, redirect the change to the table in the
    # current schema and recreate views.
    #
    def change_table(table_name, *args)
      return super unless is_chrono?(table_name)
      chrono_alter(table_name) {|current| super current, *args}
    end

    # If dropping a temporal table, drops it from the current schema
    # adding the CASCADE option so to delete the history, view and rules.
    #
    def drop_table(table_name, options = {})
      return super unless is_chrono?(table_name)

      execute "DROP TABLE #{chrono_current_table_for(table_name)} CASCADE"
    end

    # If adding a column to a temporal table, creates it in the table in
    # the current schema and updates the view rules.
    #
    def add_column(table_name, column_name, type, options = {})
      return super unless is_chrono?(table_name)

      transaction do
        # Add the column to the current table
        super chrono_current_table_for(table_name), column_name, type, options

        # Update the rules
        chrono_create_view_for(table_name)
      end
    end

    # If renaming a column of a temporal table, rename it in the table in
    # the current schema and update the view rules.
    #
    def rename_column(table_name, column_name, new_column_name)
      return super unless is_chrono?(table_name)

      # Rename the column in the current table and in the view
      transaction do
        super chrono_current_table_for(table_name), column_name, new_column_name
        super chrono_view_for(table_name), column_name, new_column_name

        # Update the rules
        chrono_create_view_for(table_name)
      end
    end

    # If removing a column from a temporal table, we are forced to drop the
    # view, then change the column from the table in the current schema and
    # eventually recreate the rules.
    #
    def change_column(table_name, *args)
      return super unless is_chrono?(table_name)
      chrono_alter(table_name) {|current| super current, *args }
    end

    # Change the default on the current schema table.
    #
    def change_column_default(table_name, *args)
      return super unless is_chrono?(table_name)
      super chrono_current_table_for(table_name), *args
    end

    # Change the null constraint on the current schema table.
    #
    def change_column_null(table_name, *args)
      return super unless is_chrono?(table_name)
      super chrono_current_table_for(table_name), *args
    end

    # If removing a column from a temporal table, we are forced to drop the
    # view, then drop the column from the table in the current schema and
    # eventually recreate the rules.
    #
    def remove_column(table_name, *column_names)
      return super unless is_chrono?(table_name)
      chrono_alter(table_name) {|current| super current, *column_names }
    end

    # Fetch columns defitions from the current schema table rather than
    # from the view, as primary key and default values are stored there
    # rather than in the view.
    def column_definitions(table_name)
      return super unless is_chrono?(table_name)
      super chrono_current_table_for(table_name)
    end

    # Fetch the primary key alone from the current schema table as the
    # view won't have this information.
    def primary_key(table_name)
      return super unless is_chrono?(table_name)
      super chrono_current_table_for(table_name)
    end

    protected
      # Returns true if the given name references a temporal table.
      #
      def is_chrono?(table)
        table_exists?(chrono_current_table_for(table)) &&
          table_exists?(chrono_history_table_for(table))
      end

    private
      def chrono_create_temporal_schemas!
        [chrono_current_schema, chrono_history_schema].each do |schema|
          execute "CREATE SCHEMA #{schema}" unless schema_exists?(schema)
        end
      end

      # Create the history table in the history schema
      def chrono_create_history_for(table)
        execute <<-SQL
          CREATE TABLE #{chrono_history_table_for(table)} (
            hid         SERIAL PRIMARY KEY,
            valid_from  timestamp NOT NULL,
            valid_to    timestamp NOT NULL DEFAULT '9999-12-31',
            recorded_at timestamp NOT NULL DEFAULT now(),

            CONSTRAINT #{table}_from_before_to CHECK (valid_from < valid_to),

            CONSTRAINT #{table}_overlapping_times EXCLUDE USING gist (
              box(
                point( extract( epoch FROM valid_from), id ),
                point( extract( epoch FROM valid_to - INTERVAL '1 millisecond'), id )
              ) with &&
            )
          ) INHERITS ( #{chrono_current_table_for(table)} )
        SQL

        # Create index for history timestamps
        execute <<-SQL
          CREATE INDEX #{table}_timestamps ON #{chrono_history_table_for(table)}
          USING btree ( valid_from, valid_to ) WITH ( fillfactor = 100 )
        SQL

        # Create index for the inherited table primary key
        execute <<-SQL
          CREATE INDEX #{table}_inherit_pkey ON #{chrono_history_table_for(table)}
          USING btree ( #{primary_key(table)} ) WITH ( fillfactor = 90 )
        SQL
      end

      # Create the public view and its rules
      def chrono_create_view_for(table)
        pk      = primary_key(table)
        view    = chrono_view_for(table)
        current = chrono_current_table_for(table)
        history = chrono_history_table_for(table)

        # SELECT - return only current data
        #
        execute "CREATE OR REPLACE VIEW #{view} AS SELECT * FROM ONLY #{current}"

        columns  = columns(table).map(&:name)
        sequence = serial_sequence(chrono_current_table_for(table), pk) # For INSERT
        updates  = columns.map {|c| "#{c} = new.#{c}"}.join(",\n")      # For UPDATE

        columns.delete(pk)

        fields, values = columns.join(', '), columns.map {|c| "new.#{c}"}.join(', ')

        # INSERT - inert data both in the current table and in the history one
        #
        execute <<-SQL
          CREATE OR REPLACE RULE #{table}_ins AS ON INSERT TO #{view} DO INSTEAD (

            INSERT INTO #{current} ( #{fields} ) VALUES ( #{values} );

            INSERT INTO #{history} ( #{pk}, #{fields}, valid_from )
            VALUES ( currval('#{sequence}'), #{values}, now() )
            RETURNING #{pk}, #{fields};
          )
        SQL

        # UPDATE - set the last history entry validity to now, save the current data
        # in a new history entry and update the current table with the new data.
        #
        execute <<-SQL
          CREATE OR REPLACE RULE #{table}_upd AS ON UPDATE TO #{view} DO INSTEAD (

            UPDATE #{history} SET valid_to = now()
            WHERE #{pk} = old.#{pk} AND valid_to = '9999-12-31';

            INSERT INTO #{history} ( #{pk}, #{fields}, valid_from )
            VALUES ( old.#{pk}, #{values}, now() );

            UPDATE ONLY #{current} SET #{updates}
            WHERE #{pk} = old.#{pk}
          )
        SQL

        # DELETE - save the current data in the history and eventually delete the data
        # from the current table.
        #
        execute <<-SQL
          CREATE OR REPLACE RULE #{table}_del AS ON DELETE TO #{view} DO INSTEAD (

            UPDATE #{history} SET valid_to = now()
            WHERE #{pk} = old.#{pk} AND valid_to = '9999-12-31';

            DELETE FROM ONLY #{current}
            WHERE #{current}.#{pk} = old.#{pk}
          )
        SQL
      end

      # In destructive changes, such as removing columns or changing column
      # types, the view must be dropped and recreated - moreover the change
      # itself must be applied to the table in the current schema, and this
      # method yields its name for convenience.
      #
      def chrono_alter(table_name)
        transaction do
          execute "DROP VIEW #{chrono_view_for(table_name)}"

          yield chrono_current_table_for(table_name)

          # Recreate the rules
          chrono_create_view_for(table_name)
        end
      end

      def chrono_current_schema
        'temporal'
      end

      def chrono_history_schema
        'history'
      end

      def chrono_current_table_for(table)
        [chrono_current_schema, table].join '.'
      end

      def chrono_history_table_for(table)
        [chrono_history_schema, table].join '.'
      end

      def chrono_view_for(table)
        "public.#{table}"
      end

  end
end

# Replace AR's PG adapter with the ChronoModel one. This (dirty) approach is
# required because the PG adapter defines +add_column+ itself, thus making
# impossible to use super() in overridden Module methods.
#
silence_warnings do
  ActiveRecord::ConnectionAdapters.const_set :PostgreSQLAdapter, ChronoModel::Adapter
end
