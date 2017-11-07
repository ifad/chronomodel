require 'active_record/tasks/chronomodel_database_tasks'

module ChronoModel
  class Railtie < ::Rails::Railtie

    rake_tasks do
      if Rails.application.config.active_record.schema_format != :sql
        raise 'In order to use ChronoModel, config.active_record.schema_format must be :sql!'
      end

      ActiveRecord::Tasks::DatabaseTasks.register_task /chronomodel/, ActiveRecord::Tasks::ChronomodelDatabaseTasks

      # Make schema:dump and schema:load invoke structure:dump and structure:load
      Rake::Task['db:schema:dump'].clear.enhance(['environment']) do
        Rake::Task['db:structure:dump'].invoke
      end

      Rake::Task['db:schema:load'].clear.enhance(['environment']) do
        Rake::Task['db:structure:load'].invoke
      end
    end

  end
end
