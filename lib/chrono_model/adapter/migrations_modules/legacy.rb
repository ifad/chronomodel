module ChronoModel
  class Adapter
    module MigrationsModules
      module Legacy
        # If adding an index to a temporal table, add it to the one in the
        # temporal schema and to the history one. If the `:unique` option is
        # present, it is removed from the index created in the history table.
        #
        def add_index(table_name, column_name, options = {})
          return super unless is_chrono?(table_name)

          transaction do
            on_temporal_schema { super }

            # Uniqueness constraints do not make sense in the history table
            options = options.dup.tap { |o| o.delete(:unique) } if options[:unique].present?

            on_history_schema { super table_name, column_name, options }
          end
        end

        # If removing an index from a temporal table, remove it both from the
        # temporal and the history schemas.
        #
        def remove_index(table_name, options = {})
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

ChronoModel::Adapter::Migrations.include ChronoModel::Adapter::MigrationsModules::Legacy
