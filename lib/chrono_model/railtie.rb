module ChronoModel
  class Railtie < ::Rails::Railtie
    ActiveRecord::Tasks::DatabaseTasks.register_task /chronomodel/, ActiveRecord::Tasks::PostgreSQLDatabaseTasks

    setup = proc { ActiveRecord::Base.connection.chrono_setup! }

    rake_tasks do
      load 'chrono_model/schema_format.rake'

      namespace :db do
        namespace(:chrono) { task :model, &setup }
      end

      task 'db:schema:load' => 'db:chrono:model'
    end
  end
end
