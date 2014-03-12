module ChronoModel
  class Railtie < ::Rails::Railtie
    ActiveRecord::Tasks::DatabaseTasks.register_task /chronomodel/, ActiveRecord::Tasks::PostgreSQLDatabaseTasks

    rake_tasks do
      load 'chrono_model/schema_format.rake'
    end
  end
end
