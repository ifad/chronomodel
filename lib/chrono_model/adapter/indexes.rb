module ChronoModel
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    module Indexes
      # Create temporal indexes for timestamp search.
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
          indexes.each { |idx| execute "DROP INDEX #{idx}" }
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

      private

        # Creates indexes for a newly made history table
        #
        def chrono_create_history_indexes_for(table, p_pkey)
          add_temporal_indexes table, :validity, on_current_schema: true

          execute "CREATE INDEX #{table}_inherit_pkey     ON #{table} ( #{p_pkey} )"
          execute "CREATE INDEX #{table}_recorded_at      ON #{table} ( recorded_at )"
          execute "CREATE INDEX #{table}_instance_history ON #{table} ( #{p_pkey}, recorded_at )"
        end

        # Rename indexes on history schema
        #
        def chrono_rename_history_indexes(name, new_name)
          on_history_schema do
            standard_index_names = %w(
              inherit_pkey instance_history pkey
              recorded_at timeline_consistency )

            old_names = temporal_index_names(name, :validity) +
              standard_index_names.map { |i| [name, i].join('_') }

            new_names = temporal_index_names(new_name, :validity) +
              standard_index_names.map { |i| [new_name, i].join('_') }

            old_names.zip(new_names).each do |old, new|
              execute "ALTER INDEX #{old} RENAME TO #{new}"
            end
          end
        end

        # Rename indexes on temporal schema
        #
        def chrono_rename_temporal_indexes(name, new_name)
          on_temporal_schema do
            temporal_indexes = indexes(new_name)
            temporal_indexes.map(&:name).each do |old_idx_name|
              if old_idx_name =~ /^index_#{name}_on_(?<columns>.+)/
                new_idx_name = "index_#{new_name}_on_#{$~['columns']}"
                execute "ALTER INDEX #{old_idx_name} RENAME TO #{new_idx_name}"
              end
            end
          end
        end

        # Copy the indexes from the temporal table to the history table
        # if the indexes are not already created with the same name.
        #
        # Uniqueness is voluntarily ignored, as it doesn't make sense on
        # history tables.
        #
        # Used in migrations.
        #
        # Ref: GitHub pull #21.
        #
        def chrono_copy_indexes_to_history(table_name)
          history_indexes  = on_history_schema  { indexes(table_name) }.map(&:name)
          temporal_indexes = on_temporal_schema { indexes(table_name) }

          temporal_indexes.each do |index|
            next if history_indexes.include?(index.name)

            on_history_schema do
              # index.columns is an Array for plain indexes,
              # while it is a String for computed indexes.
              #
              columns = Array.wrap(index.columns).join(', ')

              execute %[
                CREATE INDEX #{index.name} ON #{table_name}
                USING #{index.using} ( #{columns} )
              ], 'Copy index from temporal to history'
            end
          end
        end

        # Returns a suitable index name on the given table and for the
        # given range definition.
        #
        def temporal_index_names(table, range, options = {})
          prefix = options[:name].presence || "index_#{table}_temporal"

          # When creating computed indexes
          #
          # e.g. ends_on::timestamp + time '23:59:59'
          #
          # remove everything following the field name.
          range = range.to_s.sub(/\W.*/, '')

          [range, "lower_#{range}", "upper_#{range}"].map do |suffix|
            [prefix, 'on', suffix].join('_')
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
    end
  end
end
