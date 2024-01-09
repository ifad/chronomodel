# frozen_string_literal: true

require 'active_record/tasks/chronomodel_database_tasks'

module ChronoModel
  class Railtie < ::Rails::Railtie
    TASKS_CLASS = ActiveRecord::Tasks::ChronomodelDatabaseTasks

    # Register our database tasks under our adapter name
    ActiveRecord::Tasks::DatabaseTasks.register_task(/chronomodel/, TASKS_CLASS.to_s)

    rake_tasks do
      def task_config
        ActiveRecord::Base.connection_db_config
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
