require 'active_record'
require 'active_record/connection_adapters/postgresql_adapter'

require 'multi_json'

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

    # This is the data type used for the SCD2 validity
    RANGE_TYPE = 'tsrange'

    # Returns true whether the connection adapter supports our
    # implementation of temporal tables. Currently, Chronomodel
    # is supported starting with PostgreSQL 9.3.
    #
    def chrono_supported?
      postgresql_version >= 90300
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

      transaction do
        _on_temporal_schema { super }
        _on_history_schema { chrono_create_history_for(table_name) }

        chrono_create_view_for(table_name, options)

        TableCache.add! table_name
      end
    end

    # If renaming a temporal table, rename the history and view as well.
    #
    def rename_table(name, new_name)
      return super unless is_chrono?(name)

      clear_cache!

      transaction do
        # Rename tables
        #
        [TEMPORAL_SCHEMA, HISTORY_SCHEMA].each do |schema|
          on_schema(schema) do
            seq     = serial_sequence(name, primary_key(name))
            new_seq = seq.sub(name.to_s, new_name.to_s).split('.').last

            execute "ALTER SEQUENCE #{seq}  RENAME TO #{new_seq}"
            execute "ALTER TABLE    #{name} RENAME TO #{new_name}"
          end
        end

        # Rename indexes
        #
        pkey = primary_key(new_name)
        _on_history_schema do
          standard_index_names = %w(
            inherit_pkey instance_history pkey
            recorded_at timeline_consistency )

          old_names = temporal_index_names(name, :validity) +
            standard_index_names.map {|i| [name, i].join('_') }

          new_names = temporal_index_names(new_name, :validity) +
            standard_index_names.map {|i| [new_name, i].join('_') }

          old_names.zip(new_names).each do |old, new|
            execute "ALTER INDEX #{old} RENAME TO #{new}"
          end
        end

        # Rename functions
        #
        %w( insert update delete ).each do |func|
          execute "ALTER FUNCTION chronomodel_#{name}_#{func}() RENAME TO chronomodel_#{new_name}_#{func}"
        end

        # Rename the public view
        #
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
            chrono_create_view_for(table_name, options)
            copy_indexes_to_history_for(table_name)

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
                  nextval('#{seq}')        AS hid,
                  tsrange('#{from}', NULL) AS validity,
                  timezone('UTC', now())   AS recorded_at
                FROM #{TEMPORAL_SCHEMA}.#{table_name}
              ]
            end
          end

          chrono_alter(table_name, options) { super table_name, options, &block }
        else
          if options[:temporal] == false && is_chrono?(table_name)
            # Remove temporal features from this table
            #
            execute "DROP VIEW #{table_name}"

            _on_temporal_schema do
              %w( insert update delete ).each do |func|
                execute "DROP FUNCTION IF EXISTS #{table_name}_#{func}() CASCADE"
              end
            end

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
    # adding the CASCADE option so to delete the history, view and triggers.
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
    # the temporal schema and updates the triggers.
    #
    def add_column(table_name, *)
      return super unless is_chrono?(table_name)

      transaction do
        # Add the column to the temporal table
        _on_temporal_schema { super }

        # Update the triggers
        chrono_create_view_for(table_name)
      end
    end

    # If renaming a column of a temporal table, rename it in the table in
    # the temporal schema and update the triggers.
    #
    def rename_column(table_name, *)
      return super unless is_chrono?(table_name)

      # Rename the column in the temporal table and in the view
      transaction do
        _on_temporal_schema { super }
        super

        # Update the triggers
        chrono_create_view_for(table_name)
      end
    end

    # If removing a column from a temporal table, we are forced to drop the
    # view, then change the column from the table in the temporal schema and
    # eventually recreate the triggers.
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
    # eventually recreate the triggers.
    #
    def remove_column(table_name, *)
      return super unless is_chrono?(table_name)
      chrono_alter(table_name) { super }
    end

    # Runs column_definitions in the temporal schema, as the table there
    # defined is the source for this information.
    #
    # The default search path is included however, since the table
    # may reference types defined in other schemas, which result in their
    # names becoming schema qualified, which will cause type resolutions to fail.
    #
    define_method(:column_definitions) do |table_name|
      return super(table_name) unless is_chrono?(table_name)
      on_schema(TEMPORAL_SCHEMA + ',' + self.schema_search_path, false) { super(table_name) }
    end

    # Runs primary_key, indexes and default_sequence_name in the temporal schema,
    # as the table there defined is the source for this information.
    #
    # Moreover, the PostgreSQLAdapter +indexes+ method uses current_schema(),
    # thus this is the only (and cleanest) way to make injection work.
    #
    # Schema nesting is disabled on these calls, make sure to fetch metadata
    # from the first caller's selected schema and not from the current one.
    #
    [:primary_key, :indexes, :default_sequence_name].each do |method|
      define_method(method) do |*args|
        table_name = args.first
        return super(*args) unless is_chrono?(table_name)
        _on_temporal_schema(false) { super(*args) }
      end
    end

    # Create spatial indexes for timestamp search.
    #
    # This index is used by +TimeMachine.at+, `.current` and `.past` to
    # build the temporal WHERE clauses that fetch the state of records at
    # a single point in time.
    #
    # Parameters:
    #
    #   `table`: the table where to create indexes on
    #   `range`: the tsrange field
    #
    # Options:
    #
    #   `:name`: the index name prefix, defaults to
    #            index_{table}_temporal_on_{range / lower_range / upper_range}
    #
    def add_temporal_indexes(table, range, options = {})
      range_idx, lower_idx, upper_idx =
        temporal_index_names(table, range, options)

      chrono_alter_index(table, options) do
        execute <<-SQL
          CREATE INDEX #{range_idx} ON #{table} USING gist ( #{range} )
        SQL

        # Indexes used for precise history filtering, sorting and, in history
        # tables, by UPDATE / DELETE triggers.
        #
        execute "CREATE INDEX #{lower_idx} ON #{table} ( lower(#{range}) )"
        execute "CREATE INDEX #{upper_idx} ON #{table} ( upper(#{range}) )"
      end
    end

    def remove_temporal_indexes(table, range, options = {})
      indexes = temporal_index_names(table, range, options)

      chrono_alter_index(table, options) do
        indexes.each {|idx| execute "DROP INDEX #{idx}" }
      end
    end

    def temporal_index_names(table, range, options = {})
      prefix = options[:name].presence || "index_#{table}_temporal"

      # When creating computed indexes (e.g. ends_on::timestamp + time
      # '23:59:59'), remove everything following the field name.
      range = range.to_s.sub(/\W.*/, '')

      [range, "lower_#{range}", "upper_#{range}"].map do |suffix|
        [prefix, 'on', suffix].join('_')
      end
    end


    # Adds an EXCLUDE constraint to the given table, to assure that
    # no more than one record can occupy a definite segment on a
    # timeline.
    #
    def add_timeline_consistency_constraint(table, range, options = {})
      name = timeline_consistency_constraint_name(table)
      id   = options[:id] || primary_key(table)

      chrono_alter_constraint(table, options) do
        execute <<-SQL
          ALTER TABLE #{table} ADD CONSTRAINT #{name}
            EXCLUDE USING gist ( #{id} WITH =, #{range} WITH && )
        SQL
      end
    end

    def remove_timeline_consistency_constraint(table, options = {})
      name = timeline_consistency_constraint_name(options[:prefix] || table)

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

    TableCache = (Class.new(Hash) do
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

    rescue ActiveRecord::StatementInvalid => e
      # means that we could not change the search path to check for
      # table existence
      if is_exception_class?(e, PG::InvalidSchemaName, PG::InvalidParameterValue)
        return false
      else
        raise e
      end
    end

    def is_exception_class?(e, *klasses)
      if e.respond_to?(:original_exception)
        klasses.any? { |k| e.is_a?(k) }
      else
        klasses.any? { |k| e.message =~ /#{k.name}/ }
      end
    end

    def chrono_setup!
      chrono_create_schemas

      chrono_upgrade_structure!
    end

    # HACK: Redefine tsrange parsing support, as it is broken currently.
    #
    # This self-made API is here because currently AR4 does not support
    # open-ended ranges. The reasons are poor support in Ruby:
    #
    #   https://bugs.ruby-lang.org/issues/6864
    #
    # and an instable interface in Active Record:
    #
    #   https://github.com/rails/rails/issues/13793
    #   https://github.com/rails/rails/issues/14010
    #
    # so, for now, we are implementing our own.
    #
    class TSRange < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Range
      OID = 3908

      def cast_value(value)
        return if value == 'empty'
        return value if value.is_a?(::Array)

        extracted = extract_bounds(value)

        from = Conversions.string_to_utc_time extracted[:from]
        to   = Conversions.string_to_utc_time extracted[:to  ]

        [from, to]
      end

      def extract_bounds(value)
        from, to = value[1..-2].split(',')
        {
          from:          (value[1] == ',' || from == '-infinity') ? nil : from[1..-2],
          to:            (value[-2] == ',' || to == 'infinity') ? nil : to[1..-2],
        }
      end
    end

    def initialize_type_map(type_map)
      super.tap do
        ar_type = type_map.fetch(TSRange::OID)
        cm_type = TSRange.new(ar_type.subtype, ar_type.type)

        type_map.register_type TSRange::OID, cm_type
      end
    end

    # Copy the indexes from the temporal table to the history table if the indexes
    # are not already created with the same name.
    #
    # Uniqueness is voluntarily ignored, as it doesn't make sense on history
    # tables.
    #
    # Ref: GitHub pull #21.
    #
    def copy_indexes_to_history_for(table_name)
      history_indexes  = _on_history_schema  { indexes(table_name) }.map(&:name)
      temporal_indexes = _on_temporal_schema { indexes(table_name) }

      temporal_indexes.each do |index|
        next if history_indexes.include?(index.name)

        _on_history_schema do
          execute %[
            CREATE INDEX #{index.name} ON #{table_name}
            USING #{index.using} ( #{index.columns.join(', ')} )
          ], 'Copy index from temporal to history'
        end
      end
    end

    private
      # Create the temporal and history schemas, unless they already exist
      #
      def chrono_create_schemas
        [TEMPORAL_SCHEMA, HISTORY_SCHEMA].each do |schema|
          execute "CREATE SCHEMA #{schema}" unless schema_exists?(schema)
        end
      end

      # Upgrades existing structure for each table, if required.
      # TODO: allow upgrades from pre-0.6 structure with box() and stuff.
      #
      def chrono_upgrade_structure!
        transaction do
          current = VERSION

          _on_temporal_schema { tables }.each do |table_name|
            next unless is_chrono?(table_name)
            metadata = chrono_metadata_for(table_name)
            version = metadata['chronomodel']

            if version.blank?
              upgrade_from_legacy(table_name)
            end

            next if version == current

            logger.info "ChronoModel: upgrading #{table_name} from #{version} to #{current}"
            chrono_create_view_for(table_name)
            logger.info "ChronoModel: upgrade complete"
          end
        end
      rescue => e
        message = "ChronoModel structure upgrade failed: #{e.message}. Please drop dependent objects and then run ActiveRecord::Base.connection.chrono_setup!"

        # Quite important, output it also to stderr.
        #
        logger.error message
        $stderr.puts message
      end

      def upgrade_from_legacy(table_name)
        # roses are red
        # violets are blue
        # and this is the most boring piece of code ever
        history_table = "#{HISTORY_SCHEMA}.#{table_name}"
        p_pkey = primary_key(table_name)

        execute "ALTER TABLE #{history_table} ADD COLUMN validity tsrange;"
        execute """
          UPDATE #{history_table} SET validity = tsrange(valid_from,
            CASE WHEN extract(year from valid_to) = 9999 THEN NULL
                 ELSE valid_to
            END
          );
        """

        execute "DROP INDEX #{history_table}_temporal_on_valid_from;"
        execute "DROP INDEX #{history_table}_temporal_on_valid_from_and_valid_to;"
        execute "DROP INDEX #{history_table}_temporal_on_valid_to;"
        execute "DROP INDEX #{history_table}_inherit_pkey"
        execute "DROP INDEX #{history_table}_recorded_at"
        execute "DROP INDEX #{history_table}_instance_history"
        execute "ALTER TABLE #{history_table} DROP CONSTRAINT #{table_name}_valid_from_before_valid_to;"
        execute "ALTER TABLE #{history_table} DROP CONSTRAINT #{table_name}_timeline_consistency;"
        execute "DROP RULE #{table_name}_upd_first ON #{table_name};"
        execute "DROP RULE #{table_name}_upd_next ON #{table_name};"
        execute "DROP RULE #{table_name}_del ON #{table_name};"
        execute "DROP RULE #{table_name}_ins ON #{table_name};"
        execute "DROP TRIGGER history_ins ON #{TEMPORAL_SCHEMA}.#{table_name};"
        execute "DROP FUNCTION #{TEMPORAL_SCHEMA}.#{table_name}_ins();"
        execute "ALTER TABLE #{history_table} DROP COLUMN valid_from;"
        execute "ALTER TABLE #{history_table} DROP COLUMN valid_to;"

        execute "CREATE EXTENSION IF NOT EXISTS btree_gist;"

        chrono_create_view_for(table_name)
        _on_history_schema { add_history_validity_constraint(table_name, p_pkey) }
        _on_history_schema { chrono_create_history_indexes_for(table_name, p_pkey) }
      end

      def chrono_metadata_for(table)
        comment = select_value(
          "SELECT obj_description(#{quote(table)}::regclass)",
          "ChronoModel metadata for #{table}") if table_exists?(table)

        MultiJson.load(comment || '{}').with_indifferent_access
      end

      def chrono_metadata_set(table, metadata)
        comment = MultiJson.dump(metadata)

        execute %[
          COMMENT ON VIEW #{table} IS #{quote(comment)}
        ]
      end

      def add_history_validity_constraint(table, pkey)
        add_timeline_consistency_constraint(table, :validity, :id => pkey, :on_current_schema => true)
      end

      def remove_history_validity_constraint(table, options = {})
        remove_timeline_consistency_constraint(table, options.merge(:on_current_schema => true))
      end

      # Create the history table in the history schema
      def chrono_create_history_for(table)
        parent = "#{TEMPORAL_SCHEMA}.#{table}"
        p_pkey = primary_key(parent)

        execute <<-SQL
          CREATE TABLE #{table} (
            hid         SERIAL PRIMARY KEY,
            validity    #{RANGE_TYPE} NOT NULL,
            recorded_at timestamp NOT NULL DEFAULT timezone('UTC', now())
          ) INHERITS ( #{parent} )
        SQL

        add_history_validity_constraint(table, p_pkey)

        chrono_create_history_indexes_for(table, p_pkey)
      end

      def chrono_create_history_indexes_for(table, p_pkey = nil)
        # Duplicate because of Migrate.upgrade_indexes_for
        # TODO remove me.
        p_pkey ||= primary_key("#{TEMPORAL_SCHEMA}.#{table}")

        add_temporal_indexes table, :validity, :on_current_schema => true

        execute "CREATE INDEX #{table}_inherit_pkey     ON #{table} ( #{p_pkey} )"
        execute "CREATE INDEX #{table}_recorded_at      ON #{table} ( recorded_at )"
        execute "CREATE INDEX #{table}_instance_history ON #{table} ( #{p_pkey}, recorded_at )"
      end

      # Create the public view and its INSTEAD OF triggers
      #
      def chrono_create_view_for(table, options = nil)
        pk      = primary_key(table)
        current = [TEMPORAL_SCHEMA, table].join('.')
        history = [HISTORY_SCHEMA,  table].join('.')
        seq     = serial_sequence(current, pk)

        options ||= chrono_metadata_for(table)

        # SELECT - return only current data
        #
        execute "DROP VIEW #{table}" if table_exists? table
        execute "CREATE VIEW #{table} AS SELECT * FROM ONLY #{current}"

        # Set default values on the view (closes #12)
        #
        chrono_metadata_set(table, options.merge(:chronomodel => VERSION))

        columns(table).each do |column|
          default = column.default.nil? ? column.default_function : quote(column.default, column)
          next if column.name == pk || default.nil?

          execute "ALTER VIEW #{table} ALTER COLUMN #{column.name} SET DEFAULT #{default}"
        end

        columns = columns(table).map {|c| quote_column_name(c.name)}
        columns.delete(quote_column_name(pk))

        fields, values = columns.join(', '), columns.map {|c| "NEW.#{c}"}.join(', ')

        # Columns to be journaled. By default everything except updated_at (GH #7)
        #
        journal = if options[:journal]
          options[:journal].map {|col| quote_column_name(col)}

        elsif options[:no_journal]
          columns - options[:no_journal].map {|col| quote_column_name(col)}

        elsif options[:full_journal]
          columns

        else
          columns - [ quote_column_name('updated_at') ]
        end

        journal &= columns

        # INSERT - insert data both in the temporal table and in the history one.
        #
        # The serial sequence is invoked manually only if the PK is NULL, to
        # allow setting the PK to a specific value (think migration scenario).
        #
        execute <<-SQL
          CREATE OR REPLACE FUNCTION chronomodel_#{table}_insert() RETURNS TRIGGER AS $$
            BEGIN
              IF NEW.#{pk} IS NULL THEN
                NEW.#{pk} := nextval('#{seq}');
              END IF;

              INSERT INTO #{current} ( #{pk}, #{fields} )
              VALUES ( NEW.#{pk}, #{values} );

              INSERT INTO #{history} ( #{pk}, #{fields}, validity )
              VALUES ( NEW.#{pk}, #{values}, tsrange(timezone('UTC', now()), NULL) );

              RETURN NEW;
            END;
          $$ LANGUAGE plpgsql;

          DROP TRIGGER IF EXISTS chronomodel_insert ON #{table};

          CREATE TRIGGER chronomodel_insert INSTEAD OF INSERT ON #{table}
            FOR EACH ROW EXECUTE PROCEDURE chronomodel_#{table}_insert();
        SQL

        # UPDATE - set the last history entry validity to now, save the current data
        # in a new history entry and update the temporal table with the new data.
        #
        # If there are no changes, this trigger suppresses redundant updates.
        #
        # If a row in the history with the current ID and current timestamp already
        # exists, update it with new data. This logic makes possible to "squash"
        # together changes made in a transaction in a single history row.
        #
        # If you want to disable this behaviour, set the CHRONOMODEL_NO_SQUASH
        # environment variable. This is useful when running scenarios inside
        # cucumber, in which everything runs in the same transaction.
        #
        execute <<-SQL
          CREATE OR REPLACE FUNCTION chronomodel_#{table}_update() RETURNS TRIGGER AS $$
            DECLARE _now timestamp;
            DECLARE _hid integer;
            DECLARE _old record;
            DECLARE _new record;
            BEGIN
              IF OLD IS NOT DISTINCT FROM NEW THEN
                RETURN NULL;
              END IF;

              _old := row(#{journal.map {|c| "OLD.#{c}" }.join(', ')});
              _new := row(#{journal.map {|c| "NEW.#{c}" }.join(', ')});

              IF _old IS NOT DISTINCT FROM _new THEN
                UPDATE ONLY #{current} SET ( #{fields} ) = ( #{values} ) WHERE #{pk} = OLD.#{pk};
                RETURN NEW;
              END IF;

              _now := timezone('UTC', now());
              _hid := NULL;

              #{"SELECT hid INTO _hid FROM #{history} WHERE #{pk} = OLD.#{pk} AND lower(validity) = _now;" unless ENV['CHRONOMODEL_NO_SQUASH']}

              IF _hid IS NOT NULL THEN
                UPDATE #{history} SET ( #{fields} ) = ( #{values} ) WHERE hid = _hid;
              ELSE
                UPDATE #{history} SET validity = tsrange(lower(validity), _now)
                WHERE #{pk} = OLD.#{pk} AND upper_inf(validity);

                INSERT INTO #{history} ( #{pk}, #{fields}, validity )
                     VALUES ( OLD.#{pk}, #{values}, tsrange(_now, NULL) );
              END IF;

              UPDATE ONLY #{current} SET ( #{fields} ) = ( #{values} ) WHERE #{pk} = OLD.#{pk};

              RETURN NEW;
            END;
          $$ LANGUAGE plpgsql;

          DROP TRIGGER IF EXISTS chronomodel_update ON #{table};

          CREATE TRIGGER chronomodel_update INSTEAD OF UPDATE ON #{table}
            FOR EACH ROW EXECUTE PROCEDURE chronomodel_#{table}_update();
        SQL

        # DELETE - save the current data in the history and eventually delete the
        # data from the temporal table.
        # The first DELETE is required to remove history for records INSERTed and
        # DELETEd in the same transaction.
        #
        execute <<-SQL
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

      # In destructive changes, such as removing columns or changing column
      # types, the view must be dropped and recreated, while the change has
      # to be applied to the table in the temporal schema.
      #
      def chrono_alter(table_name, opts = {})
        transaction do
          options = chrono_metadata_for(table_name).merge(opts)

          execute "DROP VIEW #{table_name}"

          _on_temporal_schema { yield }

          # Recreate the triggers
          chrono_create_view_for(table_name, options)
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
