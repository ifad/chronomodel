module ActiveRecord
  module Tasks
    class ChronomodelDatabaseTasks < PostgreSQLDatabaseTasks

      def structure_dump(*arguments)
        original_schema_search_path = configuration['schema_search_path']

        if original_schema_search_path.present?
          configuration['schema_search_path'] = original_schema_search_path.split(',').concat([
            ChronoModel::Adapter::TEMPORAL_SCHEMA,
            ChronoModel::Adapter::HISTORY_SCHEMA
          ]).join(',')
        end

        super(*arguments)

        filename = arguments.first
        sql = File.read(filename).gsub(/CREATE SCHEMA (?!IF NOT EXISTS)/, '\&IF NOT EXISTS ')
        File.open(filename, 'w') { |file| file << sql }
        remove_sql_header_comments(filename)

        configuration['schema_search_path'] = original_schema_search_path
      end

      private


      unless method_defined? :remove_sql_header_comments
        def remove_sql_header_comments(filename)
          sql_comment_begin = '--'
          removing_comments = true
          tempfile = Tempfile.open("uncommented_structure.sql")
          begin
            File.foreach(filename) do |line|
              unless removing_comments && (line.start_with?(sql_comment_begin) || line.blank?)
                tempfile << line
                removing_comments = false
              end
            end
          ensure
            tempfile.close
          end
          FileUtils.mv(tempfile.path, filename)
        end
      end

    end
  end
end
