# frozen_string_literal: true

module ChronoModel
  class Adapter
    module MigrationsModules
      module Stable
        # Creates the given table, possibly creating the temporal schema
        # objects if the `:temporal` option is given and set to true.
        #
        def create_table(table_name, **options)
          # No temporal features requested, skip
          return super unless options[:temporal]

          if options[:id] == false
            logger.warn 'ChronoModel: Temporal Temporal tables require a primary key.'
            logger.warn "ChronoModel: Adding a `__chrono_id' primary key to #{table_name} definition."

            options[:id] = '__chrono_id'
          end

          transaction do
            pending_indexes = []
            on_temporal_schema do
              super do |table_definition|
                yield table_definition if block_given?

                # Defer indexes until both backing tables exist so add_index handles both schemas.
                pending_indexes.concat(table_definition.indexes)
                table_definition.indexes.clear
              end
            end
            on_history_schema { chrono_history_table_ddl(table_name) }

            pending_indexes.each do |columns, index_options|
              add_index(table_name, columns, **index_options, if_not_exists: options[:if_not_exists])
            end

            chrono_public_view_ddl(table_name, options)
          end
        end

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
      end
    end
  end
end

ChronoModel::Adapter::Migrations.include ChronoModel::Adapter::MigrationsModules::Stable
