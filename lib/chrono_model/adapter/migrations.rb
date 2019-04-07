module ChronoModel
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter

    module Migrations
      extend ActiveSupport::Concern

      included do
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
            on_temporal_schema(false) { super(*args) }
          end
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
      end

      # Creates the given table, possibly creating the temporal schema
      # objects if the `:temporal` option is given and set to true.
      #
      def create_table(table_name, options = {})
        # No temporal features requested, skip
        return super unless options[:temporal]

        if options[:id] == false
          logger.warn "ChronoModel: Temporal Temporal tables require a primary key."
          logger.warn "ChronoModel: Adding a `__chrono_id' primary key to #{table_name} definition."

          options[:id] = '__chrono_id'
        end

        transaction do
          on_temporal_schema { super }
          on_history_schema { chrono_create_history_for(table_name) }

          chrono_create_view_for(table_name, options)
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

          chrono_rename_history_indexes(name, new_name)
          chrono_rename_temporal_indexes(name, new_name)

          # Drop view
          #
          execute "DROP VIEW #{name}"

          # Drop functions
          #
          chrono_drop_trigger_functions_for(name)

          # Create view and functions
          #
          chrono_create_view_for(new_name)
        end
      end

      # Rename indexes on history schema
      #
      def chrono_rename_history_indexes(name, new_name)
        on_history_schema do
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
      end

      # Rename indexes on temporal schema
      #
      def chrono_rename_temporal_indexes(name, new_name)
        on_temporal_schema do
          temporal_indexes =  indexes(new_name)
          temporal_indexes.map(&:name).each do |old_idx_name|
            if old_idx_name =~ /^index_#{name}_on_(?<columns>.+)/
              new_idx_name = "index_#{new_name}_on_#{$~['columns']}"
              execute "ALTER INDEX #{old_idx_name} RENAME TO #{new_idx_name}"
            end
          end
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

          case options[:temporal]
          when true
            if !is_chrono?(table_name)
              chrono_make_temporal_table(table_name, options)
            end

            chrono_alter(table_name, options) { super table_name, options, &block }

          when false
            if is_chrono?(table_name)
              chrono_undo_temporal_table(table_name)
            end

            super table_name, options, &block
          end
        end
      end

      def chrono_make_temporal_table(table_name, options)
        # Add temporal features to this table
        #
        if !primary_key(table_name)
          execute "ALTER TABLE #{table_name} ADD __chrono_id SERIAL PRIMARY KEY"
        end

        execute "ALTER TABLE #{table_name} SET SCHEMA #{TEMPORAL_SCHEMA}"
        on_history_schema { chrono_create_history_for(table_name) }
        chrono_create_view_for(table_name, options)
        copy_indexes_to_history_for(table_name)

        # Optionally copy the plain table data, setting up history
        # retroactively.
        #
        if options[:copy_data]
          seq  = on_history_schema { serial_sequence(table_name, primary_key(table_name)) }
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
      private :chrono_make_temporal_table

      def chrono_undo_temporal_table(table_name)
        # Remove temporal features from this table
        #
        execute "DROP VIEW #{table_name}"

        chrono_drop_trigger_functions_for(table_name)

        on_history_schema { execute "DROP TABLE #{table_name}" }

        default_schema = select_value 'SELECT current_schema()'
        on_temporal_schema do
          if primary_key(table_name) == '__chrono_id'
            execute "ALTER TABLE #{table_name} DROP __chrono_id"
          end

          execute "ALTER TABLE #{table_name} SET SCHEMA #{default_schema}"
        end
      end
      private :chrono_undo_temporal_table

      # If dropping a temporal table, drops it from the temporal schema
      # adding the CASCADE option so to delete the history, view and triggers.
      #
      def drop_table(table_name, *)
        return super unless is_chrono?(table_name)

        on_temporal_schema { execute "DROP TABLE #{table_name} CASCADE" }

        chrono_drop_trigger_functions_for(table_name)
      end

      # If adding an index to a temporal table, add it to the one in the
      # temporal schema and to the history one. If the `:unique` option is
      # present, it is removed from the index created in the history table.
      #
      def add_index(table_name, column_name, options = {})
        return super unless is_chrono?(table_name)

        transaction do
          on_temporal_schema { super }

          # Uniqueness constraints do not make sense in the history table
          options = options.dup.tap {|o| o.delete(:unique)} if options[:unique].present?

          on_history_schema { super table_name, column_name, options }
        end
      end

      # If removing an index from a temporal table, remove it both from the
      # temporal and the history schemas.
      #
      def remove_index(table_name, *)
        return super unless is_chrono?(table_name)

        transaction do
          on_temporal_schema { super }
          on_history_schema { super }
        end
      end

      # If adding a column to a temporal table, creates it in the table in
      # the temporal schema and updates the triggers.
      #
      def add_column(table_name, *)
        return super unless is_chrono?(table_name)

        transaction do
          # Add the column to the temporal table
          on_temporal_schema { super }

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
          on_temporal_schema { super }
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
        on_temporal_schema { super }
      end

      # Change the null constraint on the temporal schema table.
      #
      def change_column_null(table_name, *)
        return super unless is_chrono?(table_name)
        on_temporal_schema { super }
      end

      # If removing a column from a temporal table, we are forced to drop the
      # view, then drop the column from the table in the temporal schema and
      # eventually recreate the triggers.
      #
      def remove_column(table_name, *)
        return super unless is_chrono?(table_name)
        chrono_alter(table_name) { super }
      end

      private
        # In destructive changes, such as removing columns or changing column
        # types, the view must be dropped and recreated, while the change has
        # to be applied to the table in the temporal schema.
        #
        def chrono_alter(table_name, opts = {})
          transaction do
            options = chrono_metadata_for(table_name).merge(opts)

            execute "DROP VIEW #{table_name}"

            on_temporal_schema { yield }

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
            on_temporal_schema { yield }
            on_history_schema { yield }
          else
            yield
          end
        end

        def chrono_alter_constraint(table_name, options)
          if is_chrono?(table_name) && !options[:on_current_schema]
            on_temporal_schema { yield }
          else
            yield
          end
        end
      # private
    end

  end
end
