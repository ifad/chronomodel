module ChronoModel
  class Railtie < ::Rails::Railtie
    ActiveRecord::Tasks::DatabaseTasks.register_task /chronomodel/, ActiveRecord::Tasks::PostgreSQLDatabaseTasks

    initializer :chrono_initialize do
      ActiveRecord::Base.connection.chrono_create_schemas!
    end

    rake_tasks do
      load 'chrono_model/schema_format.rake'

      namespace :db do
        namespace :chrono do
          task :model do
            ActiveRecord::Base.connection.chrono_create_schemas!
          end
        end
      end

      task 'db:schema:load' => 'db:chrono:model'
    end
  end
end
