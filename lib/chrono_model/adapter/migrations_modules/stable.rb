# frozen_string_literal: true

module ChronoModel
  class Adapter
    module MigrationsModules
      # Stable migration methods for temporal table management.
      #
      # Provides index management operations that work correctly with temporal tables,
      # ensuring indexes are created and removed from both the temporal and history schemas.
      module Stable
        # Adds an index to a temporal table.
        #
        # If adding an index to a temporal table, adds it to the one in the
        # temporal schema and to the history one. If the `:unique` option is
        # present, it is removed from the index created in the history table
        # since uniqueness constraints do not make sense in the history table.
        #
        # @param table_name [String, Symbol] the table name
        # @param column_name [String, Symbol, Array] the column name(s) to index
        # @param options [Hash] index options
        # @option options [Boolean] :unique whether the index should be unique (removed for history table)
        # @return [void]
        def add_index(table_name, column_name, **options)
          return super unless is_chrono?(table_name)

          transaction do
            on_temporal_schema { super }

            # Uniqueness constraints do not make sense in the history table
            options = options.dup.tap { |o| o.delete(:unique) } if options[:unique].present?

            on_history_schema { super }
          end
        end

        # Removes an index from a temporal table.
        #
        # If removing an index from a temporal table, removes it both from the
        # temporal and the history schemas.
        #
        # @param table_name [String, Symbol] the table name
        # @param column_name [String, Symbol, Array, nil] the column name(s) to remove index from
        # @param options [Hash] index removal options
        # @return [void]
        def remove_index(table_name, column_name = nil, **options)
          return super unless is_chrono?(table_name)

          transaction do
            on_temporal_schema { super }

            on_history_schema { super }
          end
        end
      end
    end
  end
end

ChronoModel::Adapter::Migrations.include ChronoModel::Adapter::MigrationsModules::Stable
