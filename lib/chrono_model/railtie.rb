# frozen_string_literal: true

require 'active_record/tasks/chronomodel_database_tasks'

module ChronoModel
  class Railtie < ::Rails::Railtie
    TASKS_CLASS = ActiveRecord::Tasks::ChronomodelDatabaseTasks

    def task_config
      if Rails.version < '6.1'
        ActiveRecord::Tasks::DatabaseTasks.current_config.with_indifferent_access
      else
        ActiveRecord::Base.connection_db_config
      end
    end

    # Register our database tasks under our adapter name
    if Rails.version < '5.2'
      ActiveRecord::Tasks::DatabaseTasks.register_task(/chronomodel/, TASKS_CLASS)
    else
      ActiveRecord::Tasks::DatabaseTasks.register_task(/chronomodel/, TASKS_CLASS.to_s)
    end

    rake_tasks do
      if Rails.application.config.active_record.schema_format != :sql
        raise 'In order to use ChronoModel, config.active_record.schema_format must be :sql!'
      end

      if Rails.version < '6.1'
        # Make schema:dump and schema:load invoke structure:dump and structure:load
        Rake::Task['db:schema:dump'].clear.enhance(['environment']) do
          Rake::Task['db:structure:dump'].invoke
        end

        Rake::Task['db:schema:load'].clear.enhance(['environment']) do
          Rake::Task['db:structure:load'].invoke
        end
      end

      desc 'Dumps database into db/data.NOW.sql or file specified via DUMP='
      task 'db:data:dump' => :environment do
        target = ENV['DUMP'] || Rails.root.join('db', "data.#{Time.now.to_f}.sql")
        TASKS_CLASS.new(task_config).data_dump(target)
      end

      desc 'Loads database dump from file specified via DUMP='
      task 'db:data:load' => :environment do
        source = ENV['DUMP'].presence or
          raise ArgumentError, 'Invoke as rake db:data:load DUMP=/path/to/data.sql'
        TASKS_CLASS.new(task_config).data_load(source)
      end
    end
  end
end
