require 'active_record'
require 'active_record/connection_adapters/postgresql_adapter'

module ChronoModel

  # This class implements all ActiveRecord::ConnectionAdapters::SchemaStatements
  # methods adding support for temporal extensions. It inherits from the Postgres
  # adapter for a clean override of its methods using super.
  #
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    TEMPORAL_SCHEMA = 'temporal' # The schema holding current data
    HISTORY_SCHEMA  = 'history'  # The schema holding historical data

    def chrono_supported?
      postgresql_version >= 90000
    end

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
      chrono_create_schemas!

      transaction do
        _on_temporal_schema { super }
        _on_history_schema { chrono_create_history_for(table_name) }

        chrono_create_view_for(table_name)

        TableCache.add! table_name
      end
    end

    # If renaming a temporal table, rename the history and view as well.
    #
    def rename_table(name, new_name)
      return super unless is_chrono?(name)

      clear_cache!

      transaction do
        [TEMPORAL_SCHEMA, HISTORY_SCHEMA].each do |schema|
          on_schema(schema) do
            seq     = serial_sequence(name, primary_key(name))
            new_seq = seq.sub(name.to_s, new_name.to_s).split('.').last

            execute "ALTER SEQUENCE #{seq}  RENAME TO #{new_seq}"
            execute "ALTER TABLE    #{name} RENAME TO #{new_name}"
          end
        end

        execute "ALTER VIEW #{name} RENAME TO #{new_name}"

        TableCache.del! name
        TableCache.add! new_name
      end
    end

    # If changing a temporal table, redirect the change to the table in the
    # temporal schema and recreate views.
    #
    # If the `:temporal` option is specified, enables or disables temporal
    # features on the given table. Please note that you'll lose your history
    # when demoting a temporal table to a plain one.
    #
    def change_table(table_name, options = {}, &block)
      transaction do

        # Add an empty proc to support calling change_table without a block.
        #
        block ||= proc { }

        if options[:temporal] == true
          if !is_chrono?(table_name)
            # Add temporal features to this table
            #
            execute "ALTER TABLE #{table_name} SET SCHEMA #{TEMPORAL_SCHEMA}"
            _on_history_schema { chrono_create_history_for(table_name) }
            chrono_create_view_for(table_name)

            TableCache.add! table_name
          end

          chrono_alter(table_name) { super table_name, options, &block }
        else
          if options[:temporal] == false && is_chrono?(table_name)
            # Remove temporal features from this table
            #
            execute "DROP VIEW #{table_name}"
            _on_history_schema { execute "DROP TABLE #{table_name}" }

            default_schema = select_value 'SELECT current_schema()'
            _on_temporal_schema do
              execute "ALTER TABLE #{table_name} SET SCHEMA #{default_schema}"
            end

            TableCache.del! table_name
          end

          super table_name, options, &block
        end
      end
    end

    # If dropping a temporal table, drops it from the temporal schema
    # adding the CASCADE option so to delete the history, view and rules.
    #
    def drop_table(table_name, *)
      return super unless is_chrono?(table_name)

      _on_temporal_schema { execute "DROP TABLE #{table_name} CASCADE" }

      TableCache.del! table_name
    end

    # If adding an index to a temporal table, add it to the one in the
    # temporal schema and to the history one. If the `:unique` option is
    # present, it is removed from the index created in the history table.
    #
    def add_index(table_name, column_name, options = {})
      return super unless is_chrono?(table_name)

      transaction do
        _on_temporal_schema { super }

        # Uniqueness constraints do not make sense in the history table
        options = options.dup.tap {|o| o.delete(:unique)} if options[:unique].present?

        _on_history_schema { super table_name, column_name, options }
      end
    end

    # If removing an index from a temporal table, remove it both from the
    # temporal and the history schemas.
    #
    def remove_index(table_name, *)
      return super unless is_chrono?(table_name)

      transaction do
        _on_temporal_schema { super }
        _on_history_schema { super }
      end
    end

    # If adding a column to a temporal table, creates it in the table in
    # the temporal schema and updates the view rules.
    #
    def add_column(table_name, *)
      return super unless is_chrono?(table_name)

      transaction do
        # Add the column to the temporal table
        _on_temporal_schema { super }

        # Update the rules
        chrono_create_view_for(table_name)
      end
    end

    # If renaming a column of a temporal table, rename it in the table in
    # the temporal schema and update the view rules.
    #
    def rename_column(table_name, *)
      return super unless is_chrono?(table_name)

      # Rename the column in the temporal table and in the view
      transaction do
        _on_temporal_schema { super }
        super

        # Update the rules
        chrono_create_view_for(table_name)
      end
    end

    # If removing a column from a temporal table, we are forced to drop the
    # view, then change the column from the table in the temporal schema and
    # eventually recreate the rules.
    #
    def change_column(table_name, *)
      return super unless is_chrono?(table_name)
      chrono_alter(table_name) { super }
    end

    # Change the default on the temporal schema table.
    #
    def change_column_default(table_name, *)
      return super unless is_chrono?(table_name)
      _on_temporal_schema { super }
    end

    # Change the null constraint on the temporal schema table.
    #
    def change_column_null(table_name, *)
      return super unless is_chrono?(table_name)
      _on_temporal_schema { super }
    end

    # If removing a column from a temporal table, we are forced to drop the
    # view, then drop the column from the table in the temporal schema and
    # eventually recreate the rules.
    #
    def remove_column(table_name, *)
      return super unless is_chrono?(table_name)
      chrono_alter(table_name) { super }
    end

    # Runs column_definitions, primary_key and indexes in the temporal schema,
    # as the table there defined is the source for this information.
    #
    # Moreover, the PostgreSQLAdapter +indexes+ method uses current_schema(),
    # thus this is the only (and cleanest) way to make injection work.
    #
    # Schema nesting is disabled on these calls, make sure to fetch metadata
    # from the first caller's selected schema and not from the current one.
    #
    [:column_definitions, :primary_key, :indexes].each do |method|
      define_method(method) do |table_name|
        return super(table_name) unless is_chrono?(table_name)
        _on_temporal_schema(false) { super(table_name) }
      end
    end

    # Evaluates the given block in the given +schema+ search path.
    #
    # By default, nested call are allowed, to disable this feature
    # pass +false+ as the second parameter.
    #
    def on_schema(schema, nesting = true, &block)
      @_on_schema_nesting = (@_on_schema_nesting || 0) + 1

      if nesting || @_on_schema_nesting == 1
        old_path = self.schema_search_path
        self.schema_search_path = schema
      end

      block.call

    ensure
      if (nesting || @_on_schema_nesting == 1)

        # If the transaction is aborted, any execute() call will raise
        # "transaction is aborted errors" - thus calling the Adapter's
        # setter won't update the memoized variable.
        #
        # Here we reset it to +nil+ to refresh it on the next call, as
        # there is no way to know which path will be restored when the
        # transaction ends.
        #
        if @connection.transaction_status == PGconn::PQTRANS_INERROR
          @schema_search_path = nil
        else
          self.schema_search_path = old_path
        end
      end
      @_on_schema_nesting -= 1
    end

    TableCache = (Class.new(HashWithIndifferentAccess) do
      def all         ; keys;                 ; end
      def add!  table ; self[table] = true    ; end
      def del!  table ; self[table] = nil     ; end
      def fetch table ; self[table] ||= yield ; end
    end).new

    # Returns true if the given name references a temporal table.
    #
    def is_chrono?(table)
      TableCache.fetch(table) do
        _on_temporal_schema { table_exists?(table) } &&
        _on_history_schema { table_exists?(table) }
      end
    end

    private
      def chrono_create_schemas!
        [TEMPORAL_SCHEMA, HISTORY_SCHEMA].each do |schema|
          execute "CREATE SCHEMA #{schema}" unless schema_exists?(schema)
        end
      end

      # Create the history table in the history schema
      def chrono_create_history_for(table)
        execute <<-SQL
          CREATE TABLE #{table} (
            hid         SERIAL PRIMARY KEY,
            valid_from  timestamp NOT NULL,
            valid_to    timestamp NOT NULL DEFAULT '9999-12-31',
            recorded_at timestamp NOT NULL DEFAULT timezone('UTC', now()),

            CONSTRAINT #{table}_from_before_to CHECK (valid_from < valid_to),

            CONSTRAINT #{table}_overlapping_times EXCLUDE USING gist (
              box(
                point( extract( epoch FROM valid_from), id ),
                point( extract( epoch FROM valid_to - INTERVAL '1 millisecond'), id )
              ) with &&
            )
          ) INHERITS ( #{TEMPORAL_SCHEMA}.#{table} )
        SQL

        # Create index for history timestamps
        execute <<-SQL
          CREATE INDEX #{table}_timestamps ON #{table}
          USING btree ( valid_from, valid_to ) WITH ( fillfactor = 100 )
        SQL

        # Create index for the inherited table primary key
        execute <<-SQL
          CREATE INDEX #{table}_inherit_pkey ON #{table}
          USING btree ( #{primary_key(table)} ) WITH ( fillfactor = 90 )
        SQL
      end

      # Create the public view and its rewrite rules
      #
      def chrono_create_view_for(table)
        pk      = primary_key(table)
        current = [TEMPORAL_SCHEMA, table].join('.')
        history = [HISTORY_SCHEMA,  table].join('.')

        # SELECT - return only current data
        #
        execute "CREATE OR REPLACE VIEW #{table} AS SELECT * FROM ONLY #{current}"

        columns  = columns(table).map(&:name)
        sequence = serial_sequence(current, pk)                    # For INSERT
        updates  = columns.map {|c| "#{c} = new.#{c}"}.join(",\n") # For UPDATE

        columns.delete(pk)

        fields, values = columns.join(', '), columns.map {|c| "new.#{c}"}.join(', ')

        # INSERT - inert data both in the temporal table and in the history one.
        #
        execute <<-SQL
          CREATE OR REPLACE RULE #{table}_ins AS ON INSERT TO #{table} DO INSTEAD (

            INSERT INTO #{current} ( #{fields} ) VALUES ( #{values} );

            INSERT INTO #{history} ( #{pk}, #{fields}, valid_from )
            VALUES ( currval('#{sequence}'), #{values}, timezone('UTC', now()) )
            RETURNING #{pk}, #{fields}
          )
        SQL

        # UPDATE - set the last history entry validity to now, save the current data
        # in a new history entry and update the temporal table with the new data.
        #
        execute <<-SQL
          CREATE OR REPLACE RULE #{table}_upd AS ON UPDATE TO #{table} DO INSTEAD (

            UPDATE #{history} SET valid_to = timezone('UTC', now())
            WHERE #{pk} = old.#{pk} AND valid_to = '9999-12-31';

            INSERT INTO #{history} ( #{pk}, #{fields}, valid_from )
            VALUES ( old.#{pk}, #{values}, timezone('UTC', now()) );

            UPDATE ONLY #{current} SET #{updates}
            WHERE #{pk} = old.#{pk}
          )
        SQL

        # DELETE - save the current data in the history and eventually delete the data
        # from the temporal table.
        #
        execute <<-SQL
          CREATE OR REPLACE RULE #{table}_del AS ON DELETE TO #{table} DO INSTEAD (

            UPDATE #{history} SET valid_to = timezone('UTC', now())
            WHERE #{pk} = old.#{pk} AND valid_to = '9999-12-31';

            DELETE FROM ONLY #{current}
            WHERE #{current}.#{pk} = old.#{pk}
          )
        SQL
      end

      # In destructive changes, such as removing columns or changing column
      # types, the view must be dropped and recreated, while the change has
      # to be applied to the table in the temporal schema.
      #
      def chrono_alter(table_name)
        transaction do
          execute "DROP VIEW #{table_name}"

          _on_temporal_schema { yield }

          # Recreate the rules
          chrono_create_view_for(table_name)
        end
      end

      def _on_temporal_schema(nesting = true, &block)
        on_schema(TEMPORAL_SCHEMA, nesting, &block)
      end

      def _on_history_schema(nesting = true, &block)
        on_schema(HISTORY_SCHEMA, nesting, &block)
      end
  end

end
