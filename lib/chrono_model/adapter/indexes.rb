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
    end

  end
end
