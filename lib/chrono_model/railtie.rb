# frozen_string_literal: true

require_relative '../active_record/tasks/chronomodel_database_tasks'

module ChronoModel
  # Rails integration for ChronoModel database adapter.
  #
  # Registers database tasks and provides Rake tasks for data dumping and loading
  # specific to ChronoModel's temporal database functionality.
  class Railtie < ::Rails::Railtie
    # @return [Class] the database tasks class for ChronoModel operations
    TASKS_CLASS = ActiveRecord::Tasks::ChronomodelDatabaseTasks

    # Register our database tasks under our adapter name
    ActiveRecord::Tasks::DatabaseTasks.register_task(/chronomodel/, TASKS_CLASS.to_s)

    rake_tasks do
      # Returns the task configuration from the current database connection.
      #
      # @return [ActiveRecord::DatabaseConfigurations::DatabaseConfig] database configuration
      # @api private
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
