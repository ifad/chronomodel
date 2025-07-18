# frozen_string_literal: true

module ChronoModel
  class Adapter
    module MigrationsModules
      module Stable
        # If adding an index to a temporal table, add it to the one in the
        # temporal schema and to the history one. If the `:unique` option is
        # present, it is removed from the index created in the history table.
        #
        def add_index(table_name, column_name, **options)
          return super unless is_chrono?(table_name)

          transaction do
            on_temporal_schema { super }

            # Uniqueness constraints do not make sense in the history table
            options = options.dup.tap { |o| o.delete(:unique) } if options[:unique].present?

            on_history_schema { super }
          end
        end

        # If removing an index from a temporal table, remove it both from the
        # temporal and the history schemas.
        #
        def remove_index(table_name, column_name = nil, **options)
          return super unless is_chrono?(table_name)

          transaction do
            on_temporal_schema { super }

            on_history_schema { super }
          end
        end

        def add_foreign_key(from_table, to_table, **options)
          to_table_schema, _ = extract_schema_and_table(to_table)

          if to_table_schema.nil? && is_chrono?(to_table) != is_chrono?(from_table)
            schema = is_chrono?(to_table) ? TEMPORAL_SCHEMA : outer_schema
            to_table = "#{schema}.#{to_table}"
          end

          return super unless is_chrono?(from_table)

          on_temporal_schema { super }
        end

        def remove_foreign_key(from_table, to_table = nil, **options)
          to_table_schema, _ = extract_schema_and_table(to_table)

          if to_table_schema.nil? && is_chrono?(to_table) != is_chrono?(from_table)
            schema = is_chrono?(to_table) ? TEMPORAL_SCHEMA : outer_schema
            to_table = "#{schema}.#{to_table}"
          end

          return super unless is_chrono?(from_table)

          on_temporal_schema { super }
        end
      end
    end
  end
end

ChronoModel::Adapter::Migrations.include ChronoModel::Adapter::MigrationsModules::Stable
