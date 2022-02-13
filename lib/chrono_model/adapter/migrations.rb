module ChronoModel
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter

    module Migrations
      # Creates the given table, possibly creating the temporal schema
      # objects if the `:temporal` option is given and set to true.
      #
      def create_table(table_name, **options)
        # No temporal features requested, skip
        return super unless options[:temporal]

        if options[:id] == false
          logger.warn "ChronoModel: Temporal Temporal tables require a primary key."
          logger.warn "ChronoModel: Adding a `__chrono_id' primary key to #{table_name} definition."

          options[:id] = '__chrono_id'
        end

        transaction do
          on_temporal_schema { super }
          on_history_schema { chrono_history_table_ddl(table_name) }

          chrono_public_view_ddl(table_name, options)
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
          on_temporal_schema { rename_table_and_pk(name, new_name) }
          on_history_schema  { rename_table_and_pk(name, new_name) }

          # Rename indexes
          #
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
          chrono_public_view_ddl(new_name)
        end
      end

      # If changing a temporal table, redirect the change to the table in the
      # temporal schema and recreate views.
      #
      # If the `:temporal` option is specified, enables or disables temporal
      # features on the given table. Please note that you'll lose your history
      # when demoting a temporal table to a plain one.
      #
      def change_table(table_name, **options, &block)
        transaction do

          # Add an empty proc to support calling change_table without a block.
          #
          block ||= proc { }

          if options[:temporal]
            if !is_chrono?(table_name)
              chrono_make_temporal_table(table_name, options)
            end

            drop_and_recreate_public_view(table_name, options) do
              super table_name, **options, &block
            end

          else
            if is_chrono?(table_name)
              chrono_undo_temporal_table(table_name)
            end

            super table_name, **options, &block
          end

        end
      end

      # If dropping a temporal table, drops it from the temporal schema
      # adding the CASCADE option so to delete the history, view and triggers.
      #
      def drop_table(table_name, **options)
        return super unless is_chrono?(table_name)

        on_temporal_schema { execute "DROP TABLE #{table_name} CASCADE" }

        chrono_drop_trigger_functions_for(table_name)
      end

      # If adding a column to a temporal table, creates it in the table in
      # the temporal schema and updates the triggers.
      #
      def add_column(table_name, column_name, type, **options)
        return super unless is_chrono?(table_name)

        transaction do
          # Add the column to the temporal table
          on_temporal_schema { super }

          # Update the triggers
          chrono_public_view_ddl(table_name)
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
          chrono_public_view_ddl(table_name)
        end
      end

      # If removing a column from a temporal table, we are forced to drop the
      # view, then change the column from the table in the temporal schema and
      # eventually recreate the triggers.
      #
      def change_column(table_name, *)
        return super unless is_chrono?(table_name)
        drop_and_recreate_public_view(table_name) { super }
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
        drop_and_recreate_public_view(table_name) { super }
      end

      private
        # In destructive changes, such as removing columns or changing column
        # types, the view must be dropped and recreated, while the change has
        # to be applied to the table in the temporal schema.
        #
        def drop_and_recreate_public_view(table_name, opts = {})
          transaction do
            options = chrono_metadata_for(table_name).merge(opts)

            execute "DROP VIEW #{table_name}"

            on_temporal_schema { yield }

            # Recreate the triggers
            chrono_public_view_ddl(table_name, options)
          end
        end

        def chrono_make_temporal_table(table_name, options)
          # Add temporal features to this table
          #
          if !primary_key(table_name)
            execute "ALTER TABLE #{table_name} ADD __chrono_id SERIAL PRIMARY KEY"
          end

          execute "ALTER TABLE #{table_name} SET SCHEMA #{TEMPORAL_SCHEMA}"
          on_history_schema { chrono_history_table_ddl(table_name) }
          chrono_public_view_ddl(table_name, options)
          chrono_copy_indexes_to_history(table_name)

          # Optionally copy the plain table data, setting up history
          # retroactively.
          #
          if options[:copy_data]
            chrono_copy_temporal_to_history(table_name, options)
          end
        end

        def chrono_copy_temporal_to_history(table_name, options)
          seq  = on_history_schema { pk_and_sequence_for(table_name).last.to_s }
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

        # Removes temporal features from this table
        #
        def chrono_undo_temporal_table(table_name)
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

        # Renames a table and its primary key sequence name
        #
        def rename_table_and_pk(name, new_name)
          seq     = pk_and_sequence_for(name).last.to_s
          new_seq = seq.sub(name.to_s, new_name.to_s).split('.').last

          execute "ALTER SEQUENCE #{seq}  RENAME TO #{new_seq}"
          execute "ALTER TABLE    #{name} RENAME TO #{new_name}"
        end

      # private
    end

  end
end
