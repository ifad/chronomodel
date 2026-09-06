# frozen_string_literal: true

module ChronoModel
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    module Columns
      # Runs column_definitions in the temporal schema, as the table there
      # defined is the source for this information.
      #
      # The default search path is included however, since the table
      # may reference types defined in other schemas, which result in their
      # names becoming schema qualified, which will cause type resolutions to fail.
      def column_definitions(table_name)
        return super unless is_chrono?(table_name)

        on_schema("#{TEMPORAL_SCHEMA},#{schema_search_path}", recurse: :ignore) { super }
      end

      private

      if ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.private_method_defined?(:fetch_column_definitions)
        # Rails 8.2 batches metadata lookups, bypassing column_definitions.
        def fetch_column_definitions(table_names)
          chrono_table_names, regular_table_names = table_names.partition { |table_name| is_chrono?(table_name) }
          definitions = table_names.index_with(nil)

          definitions.merge!(super(regular_table_names))

          unless chrono_table_names.empty?
            on_schema("#{TEMPORAL_SCHEMA},#{schema_search_path}", recurse: :ignore) do
              definitions.merge!(super(chrono_table_names))
            end
          end

          definitions
        end
      end
    end
  end
end
