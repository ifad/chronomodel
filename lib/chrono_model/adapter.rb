require 'active_record'
require 'active_record/connection_adapters/postgresql_adapter'

module ChronoModel

  # This class implements all ActiveRecord::ConnectionAdapters::SchemaStatements
  # methods adding support for temporal extensions. It inherits from the Postgres
  # adapter for a clean override of its methods using super.
  #
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    # The schema holding current data
    TEMPORAL_SCHEMA = 'temporal'

    # The schema holding historical data
    HISTORY_SCHEMA  = 'history'

    # Chronomodel is supported starting with PostgreSQL >= 9.0
    #
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
        logger.warn "WARNING - Temporal Temporal tables require a primary key."
        logger.warn "WARNING - Creating a \"__chrono_id\" primary key to fulfill the requirement"

        options[:id] = '__chrono_id'
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
            if !primary_key(table_name)
              execute "ALTER TABLE #{table_name} ADD __chrono_id SERIAL PRIMARY KEY"
            end

            execute "ALTER TABLE #{table_name} SET SCHEMA #{TEMPORAL_SCHEMA}"
            _on_history_schema { chrono_create_history_for(table_name) }
            chrono_create_view_for(table_name)

            TableCache.add! table_name

            # Optionally copy the plain table data, setting up history
            # retroactively.
            #
            if options[:copy_data]
              seq  = _on_history_schema { serial_sequence(table_name, primary_key(table_name)) }
              from = options[:validity] || '0001-01-01 00:00:00'

              execute %[
                INSERT INTO #{HISTORY_SCHEMA}.#{table_name}
                SELECT *,
                  nextval('#{seq}')               AS hid,
                  timestamp '#{from}'             AS valid_from,
                  timestamp '9999-12-31 00:00:00' AS valid_to,
                  timezone('UTC', now())          AS recorded_at
                FROM #{TEMPORAL_SCHEMA}.#{table_name}
              ]
            end
          end

          chrono_alter(table_name) { super table_name, options, &block }
        else
          if options[:temporal] == false && is_chrono?(table_name)
            # Remove temporal features from this table
            #
            execute "DROP VIEW #{table_name}"
            _on_temporal_schema { execute "DROP FUNCTION IF EXISTS #{table_name}_ins() CASCADE" }
            _on_history_schema { execute "DROP TABLE #{table_name}" }

            default_schema = select_value 'SELECT current_schema()'
            _on_temporal_schema do
              if primary_key(table_name) == '__chrono_id'
                execute "ALTER TABLE #{table_name} DROP __chrono_id"
              end

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

    # Create spatial indexes for timestamp search. Conceptually identical
    # to the EXCLUDE constraint in chrono_create_history_for, but without
    # the millisecond skew.
    #
    # This index is used by +TimeMachine.at+, `.current` and `.past` to
    # build the temporal WHERE clauses that fetch the state of records at
    # a single point in time.
    #
    # Parameters:
    #
    #   `table`: the table where to create indexes on
    #   `from` : the starting timestamp field
    #   `to`   : the ending timestamp field
    #
    # Options:
    #
    #   `:name`: the index name prefix, defaults to
    #            {table_name}_temporal_{snapshot / from_col / to_col}
    #
    def add_temporal_indexes(table, from, to, options = {})
      snapshot_idx, from_idx, to_idx =
        temporal_index_names(table, from, to, options)

      chrono_alter_index(table, options) do
        execute <<-SQL
          CREATE INDEX #{snapshot_idx} ON #{table} USING gist (
            box(
              point( date_part( 'epoch', #{from} ), 0 ),
              point( date_part( 'epoch', #{to  } ), 0 )
            )
          )
        SQL

        # Indexes used for precise history filtering, sorting and, in history
        # tables, by UPDATE / DELETE rules
        #
        execute "CREATE INDEX #{from_idx} ON #{table} ( #{from} )"
        execute "CREATE INDEX #{to_idx  } ON #{table} ( #{to  } )"
      end
    end

    def remove_temporal_indexes(table, from, to, options = {})
      indexes = temporal_index_names(table, from, to, options)

      chrono_alter_index(table, options) do
        indexes.each {|idx| execute "DROP INDEX #{idx}" }
      end
    end

    def temporal_index_names(table, from, to, options)
      prefix = options[:name].presence || "#{table}_temporal"

      ["#{from}_and_#{to}", from, to].map do |suffix|
        [prefix, 'on', suffix].join('_')
      end
    end


    # Adds a CHECK constraint to the given +table+, to assure that
    # the value contained in the +from+ field is, by default, less
    # than the value contained in the +to+ field.
    #
    # The default `<` operator can be changed using the `:op` option.
    #
    def add_from_before_to_constraint(table, from, to, options = {})
      operator = options[:op].presence || '<'
      name = from_before_to_constraint_name(table, from, to)

      chrono_alter_constraint(table, options) do
        execute <<-SQL
          ALTER TABLE #{table} ADD CONSTRAINT
            #{name} CHECK (#{from} #{operator} #{to})
        SQL
      end
    end

    def remove_from_before_to_constraint(table, from, to, options = {})
      name = from_before_to_constraint_name(table, from, to)

      chrono_alter_constraint(table, options) do
        execute <<-SQL
          ALTER TABLE #{table} DROP CONSTRAINT #{name}
        SQL
      end
    end

    def from_before_to_constraint_name(table, from, to)
      "#{table}_#{from}_before_#{to}"
    end


    # Adds an EXCLUDE constraint to the given table, to assure that
    # no more than one record can occupy a definite segment on a
    # timeline.
    #
    # The exclusion is implemented using a spatial gist index, that
    # uses boxes under the hood. Different records are identified by
    # default using the table's primary key - or you can specify your
    # field (or composite field) using the `:id` option.
    #
    def add_timeline_consistency_constraint(table, from, to, options = {})
      name = timeline_consistency_constraint_name(table)
      id = options[:id] || primary_key(table)

      chrono_alter_constraint(table, options) do
        execute <<-SQL
          ALTER TABLE #{table} ADD CONSTRAINT
            #{name} EXCLUDE USING gist (
              box(
                point( date_part( 'epoch', #{from} ), #{id} ),
                point( date_part( 'epoch', #{to  } - INTERVAL '1 msec' ), #{id} )
              )
              WITH &&
            )
        SQL
      end
    end

    def remove_timeline_consistency_constraint(table, from, to, options = {})
      name = timeline_consistency_constraint_name(table)
      chrono_alter_constraint(table, options) do
        execute <<-SQL
          ALTER TABLE #{table} DROP CONSTRAINT #{name}
        SQL
      end
    end

    def timeline_consistency_constraint_name(table)
      "#{table}_timeline_consistency"
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
      def all         ; keys;                      ; end
      def add!  table ; self[table.to_s] = true    ; end
      def del!  table ; self[table.to_s] = nil     ; end
      def fetch table ; self[table.to_s] ||= yield ; end
    end).new

    # Returns true if the given name references a temporal table.
    #
    def is_chrono?(table)
      TableCache.fetch(table) do
        _on_temporal_schema { table_exists?(table) } &&
        _on_history_schema { table_exists?(table) }
      end
    # means that we could not change the search path to check for
    # table existence
    rescue PG::InvalidSchemaName
      false
    end

    def chrono_create_schemas!
      [TEMPORAL_SCHEMA, HISTORY_SCHEMA].each do |schema|
        execute "CREATE SCHEMA #{schema}" unless schema_exists?(schema)
      end
    end

    # Disable savepoints support, as they break history keeping.
    # http://archives.postgresql.org/pgsql-hackers/2012-08/msg01094.php
    #
    def supports_savepoints?
      false
    end

    def create_savepoint; end
    def rollback_to_savepoint; end
    def release_savepoint; end

    private
      # Create the history table in the history schema
      def chrono_create_history_for(table)
        parent = "#{TEMPORAL_SCHEMA}.#{table}"
        p_pkey = primary_key(parent)

        execute <<-SQL
          CREATE TABLE #{table} (
            hid         SERIAL PRIMARY KEY,
            valid_from  timestamp NOT NULL,
            valid_to    timestamp NOT NULL DEFAULT '9999-12-31',
            recorded_at timestamp NOT NULL DEFAULT timezone('UTC', now())
          ) INHERITS ( #{parent} )
        SQL

        add_from_before_to_constraint(table, :valid_from, :valid_to,
          :on_current_schema => true)

        add_timeline_consistency_constraint(table, :valid_from, :valid_to,
          :id => p_pkey, :on_current_schema => true)

        # Inherited primary key
        execute "CREATE INDEX #{table}_inherit_pkey ON #{table} ( #{p_pkey} )"

        chrono_create_history_indexes_for(table, p_pkey)
      end

      def chrono_create_history_indexes_for(table, p_pkey = nil)
        # Duplicate because of Migrate.upgrade_indexes_for
        # TODO remove me.
        p_pkey ||= primary_key("#{TEMPORAL_SCHEMA}.#{table}")

        add_temporal_indexes table, :valid_from, :valid_to,
          :on_current_schema => true

        execute "CREATE INDEX #{table}_recorded_at      ON #{table} ( recorded_at )"
        execute "CREATE INDEX #{table}_instance_history ON #{table} ( #{p_pkey}, recorded_at )"
      end

      # Create the public view and its rewrite rules
      #
      def chrono_create_view_for(table)
        pk      = primary_key(table)
        current = [TEMPORAL_SCHEMA, table].join('.')
        history = [HISTORY_SCHEMA,  table].join('.')

        # SELECT - return only current data
        #
        execute "DROP VIEW #{table}" if table_exists? table
        execute "CREATE VIEW #{table} AS SELECT *, xmin AS __xid FROM ONLY #{current}"

        columns = columns(table).map{|c| quote_column_name(c.name)}
        columns.delete(quote_column_name(pk))

        updates = columns.map {|c| "#{c} = new.#{c}"}.join(",\n")

        fields, values = columns.join(', '), columns.map {|c| "new.#{c}"}.join(', ')
        fields_with_pk, values_with_pk = "#{pk}, " << fields, "new.#{pk}, " << values

        # INSERT - insert data both in the temporal table and in the history one.
        #
        # A trigger is required if there is a serial ID column, as rules by
        # design cannot handle the following case:
        #
        #   * INSERT INTO ... SELECT: if using currval(), all the rows
        #     inserted in the history will have the same identity value;
        #
        #   * if using a separate sequence to solve the above case, it may go
        #     out of sync with the main one if an INSERT statement fails due
        #     to a table constraint (the first one is nextval()'ed but the
        #     nextval() on the history one never happens)
        #
        # So, only for this case, we resort to an AFTER INSERT FOR EACH ROW trigger.
        #
        # Ref: GH Issue #4.
        #
        if serial_sequence(current, pk).present?
          execute <<-SQL
            CREATE RULE #{table}_ins AS ON INSERT TO #{table} DO INSTEAD (
              INSERT INTO #{current} ( #{fields} ) VALUES ( #{values} )
              RETURNING #{pk}, #{fields}, xmin
            );

            CREATE OR REPLACE FUNCTION #{current}_ins() RETURNS TRIGGER AS $$
              BEGIN
                INSERT INTO #{history} ( #{fields_with_pk}, valid_from )
                VALUES ( #{values_with_pk}, timezone('UTC', now()) );
                RETURN NULL;
              END;
            $$ LANGUAGE plpgsql;

            DROP TRIGGER IF EXISTS history_ins ON #{current};

            CREATE TRIGGER history_ins AFTER INSERT ON #{current}
              FOR EACH ROW EXECUTE PROCEDURE #{current}_ins();
          SQL
        else
          execute <<-SQL
            CREATE RULE #{table}_ins AS ON INSERT TO #{table} DO INSTEAD (

              INSERT INTO #{current} ( #{fields_with_pk} ) VALUES ( #{values_with_pk} );

              INSERT INTO #{history} ( #{fields_with_pk}, valid_from )
              VALUES ( #{values_with_pk}, timezone('UTC', now()) )
              RETURNING #{fields_with_pk}, xmin
            )
          SQL
        end

        # UPDATE - set the last history entry validity to now, save the current data
        # in a new history entry and update the temporal table with the new data.

        # If this is the first statement of a transaction, inferred by the last
        # transaction ID that updated the row, create a new row in the history.
        #
        # The current transaction ID is returned by txid_current() as a 64-bit
        # signed integer, while the last transaction ID that changed a row is
        # stored into a 32-bit unsigned integer in the __xid column. As XIDs
        # wrap over time, txid_current() adds an "epoch" counter in the most
        # significant bits (http://bit.ly/W2Srt7) of the int - thus here we
        # remove it by and'ing with 2^32-1.
        #
        # XID are 32-bit unsigned integers, and by design cannot be casted nor
        # compared to anything else, adding a CAST or an operator requires
        # super-user privileges, so here we do a double-cast from varchar to
        # int8, to finally compare it with the current XID. We're using 64bit
        # integers as in PG there is no 32-bit unsigned data type.
        #
        execute <<-SQL
          CREATE RULE #{table}_upd_first AS ON UPDATE TO #{table}
          WHERE old.__xid::char(10)::int8 <> (txid_current() & (2^32-1)::int8)
          DO INSTEAD (

            UPDATE #{history} SET valid_to = timezone('UTC', now())
            WHERE #{pk} = old.#{pk} AND valid_to = '9999-12-31';

            INSERT INTO #{history} ( #{pk}, #{fields}, valid_from )
            VALUES ( old.#{pk}, #{values}, timezone('UTC', now()) );

            UPDATE ONLY #{current} SET #{updates}
            WHERE #{pk} = old.#{pk}
          )
        SQL

        # Else, update the already present history row with new data. This logic
        # makes possible to "squash" together changes made in a transaction in a
        # single history row, assuring timestamps consistency.
        #
        execute <<-SQL
          CREATE RULE #{table}_upd_next AS ON UPDATE TO #{table} DO INSTEAD (
            UPDATE #{history} SET #{updates}
            WHERE #{pk} = old.#{pk} AND valid_from = timezone('UTC', now());

            UPDATE ONLY #{current} SET #{updates}
            WHERE #{pk} = old.#{pk}
          )
        SQL

        # DELETE - save the current data in the history and eventually delete the
        # data from the temporal table.
        # The first DELETE is required to remove history for records INSERTed and
        # DELETEd in the same transaction.
        #
        execute <<-SQL
          CREATE RULE #{table}_del AS ON DELETE TO #{table} DO INSTEAD (

            DELETE FROM #{history}
            WHERE #{pk} = old.#{pk}
              AND valid_from = timezone('UTC', now())
              AND valid_to   = '9999-12-31';

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

      # Generic alteration of history tables, where changes have to be
      # propagated both on the temporal table and the history one.
      #
      # Internally, the :on_current_schema bypasses the +is_chrono?+
      # check, as some temporal indexes and constraints are created
      # only on the history table, and the creation methods already
      # run scoped into the correct schema.
      #
      def chrono_alter_index(table_name, options)
        if is_chrono?(table_name) && !options[:on_current_schema]
          _on_temporal_schema { yield }
          _on_history_schema { yield }
        else
          yield
        end
      end

      def chrono_alter_constraint(table_name, options)
        if is_chrono?(table_name) && !options[:on_current_schema]
          _on_temporal_schema { yield }
        else
          yield
        end
      end

      def _on_temporal_schema(nesting = true, &block)
        on_schema(TEMPORAL_SCHEMA, nesting, &block)
      end

      def _on_history_schema(nesting = true, &block)
        on_schema(HISTORY_SCHEMA, nesting, &block)
      end

      def translate_exception(exception, message)
        if exception.message =~ /conflicting key value violates exclusion constraint/
          ActiveRecord::RecordNotUnique.new(message, exception)
        else
          super
        end
      end
  end

end
