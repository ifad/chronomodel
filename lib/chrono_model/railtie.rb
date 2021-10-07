require 'active_record/tasks/chronomodel_database_tasks'

module ChronoModel
  class Railtie < ::Rails::Railtie

    rake_tasks do
      if Rails.application.config.active_record.schema_format != :sql
        raise 'In order to use ChronoModel, config.active_record.schema_format must be :sql!'
      end

      tasks_class = ActiveRecord::Tasks::ChronomodelDatabaseTasks

      # Register our database tasks under our adapter name
      #
      ActiveRecord::Tasks::DatabaseTasks.register_task(/chronomodel/, tasks_class)

      if Rails.version <= '6.1'
        # Make schema:dump and schema:load invoke structure:dump and structure:load
        Rake::Task['db:schema:dump'].clear.enhance(['environment']) do
          Rake::Task['db:structure:dump'].invoke
        end

        Rake::Task['db:schema:load'].clear.enhance(['environment']) do
          Rake::Task['db:structure:load'].invoke
        end
      end

      desc "Dumps database into db/data.NOW.sql or file specified via DUMP="
      task 'db:data:dump' => :environment do
        config = ActiveRecord::Tasks::DatabaseTasks.current_config
        target = ENV['DUMP'] || Rails.root.join('db', "data.#{Time.now.to_f}.sql")

        tasks_class.new(config).data_dump(target)
      end

      desc "Loads database dump from file specified via DUMP="
      task 'db:data:load' => :environment do
        config = ActiveRecord::Tasks::DatabaseTasks.current_config
        source = ENV['DUMP'].presence or
          raise ArgumentError, "Invoke as rake db:data:load DUMP=/path/to/data.sql"

        tasks_class.new(config).data_load(source)
      end
    end

  end
end
