module ChronoModel
  class Railtie < ::Rails::Railtie
    initializer :chrono_create_schemas do
      ActiveRecord::Base.connection.chrono_create_schemas!
    end

    rake_tasks do

     namespace :db do
       namespace :chrono do
         task :create_schemas do
           puts 'create schemas'
           ActiveRecord::Base.connection.chrono_create_schemas!
         end
       end
     end

      task 'db:schema:load' => 'db:chrono:create_schemas'
    end
  end
end
