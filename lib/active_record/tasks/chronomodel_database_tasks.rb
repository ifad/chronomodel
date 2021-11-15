module ActiveRecord
  module Tasks
    class ChronomodelDatabaseTasks < PostgreSQLDatabaseTasks

      def structure_dump(*arguments)

        with_chronomodel_schema_search_path do
          super(*arguments)
        end

        # The structure.sql includes CREATE SCHEMA statements, but as these are executed
        # when the connection to the database is established, a db:structure:load fails.
        #
        # This code adds the IF NOT EXISTS clause to CREATE SCHEMA statements as long as
        # it is not already present.
        #
        filename = arguments.first
        sql = File.read(filename).gsub(/CREATE SCHEMA (?!IF NOT EXISTS)/, '\&IF NOT EXISTS ')
        File.open(filename, 'w') { |file| file << sql }

        remove_sql_header_comments(filename)
      end

      def data_dump(target)
        set_psql_env

        args = ['-c', '-f', target.to_s]
        args << configuration[:database]

        run_cmd "pg_dump", args, 'dumping data'
      end

      def data_load(source)
        set_psql_env

        args = ['-f', source]
        args << configuration[:database]

        run_cmd "psql", args, 'loading data'
      end

      private

      def configuration
        # In Rails 6.1.x the configuration instance variable is not available
        # and it's been replaced by @configuration_hash (which is frozen).
        @configuration ||= @configuration_hash.dup
      end

      # If a schema search path is defined in the configuration file, it will
      # be used by the database tasks class to dump only the specified search
      # path. Here we add also ChronoModel's temporal and history schemas to
      # the search path and yield.
      #
      def with_chronomodel_schema_search_path
        original_schema_search_path = configuration['schema_search_path']

        if original_schema_search_path.present?
          configuration['schema_search_path'] = original_schema_search_path.split(',').concat([
            ChronoModel::Adapter::TEMPORAL_SCHEMA,
            ChronoModel::Adapter::HISTORY_SCHEMA
          ]).join(',')
        end

        yield

      ensure
        configuration['schema_search_path'] = original_schema_search_path
      end

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
