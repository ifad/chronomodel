import File.expand_path(File.dirname(__FILE__) + '/schema_format.rb')

namespace :db do
  # Define PG environment utility methods
  task :pg_env => :environment do
    def pg_get_config
      ActiveRecord::Base.configurations.fetch(Rails.env).tap do |config|
        ENV['PGHOST']     = config['host'].to_s     if config.key?('host')
        ENV['PGPORT']     = config['port'].to_s     if config.key?('port')
        ENV['PGPASSWORD'] = config['password'].to_s if config.key?('password')
      end
    end

    def pg_make_dump(target, username, database)
      %x( pg_dump -f #{target} -c -U #{username} #{database} )
    end

    def pg_load_dump(source, username, database, template = nil)
      %x( psql -U "#{username}" -f #{source} #{database} #{template} )
    end
  end

  namespace :structure do
    desc "Load structure.sql file into the current environment's database"
    task :load => :pg_env do
      # Loads the db/structure.sql file into current environment's database.
      #
      pg_load_dump Rails.root.join('db/structure.sql').to_s,
        *pg_get_config.values_at('username', 'database', 'template')
    end
  end

  namespace :data do
    desc "Save a dump of the database in ENV['DUMP'] or db/data.NOW.sql"
    task :dump => :pg_env do
      target = ENV['DUMP'] || Rails.root.join('db', "data.#{Time.now.to_f}.sql")

      print "** Dumping data to #{target}..."
      pg_make_dump target, *pg_get_config.values_at('username', 'database')
      puts 'done'
    end

    desc "Load a dump of the database from ENV['DUMP']"
    task :load => :pg_env do
      source = ENV['DUMP'].presence or
        raise ArgumentError, "Invoke as rake db:data:load DUMP=/path/to/data.sql"

      print "** Restoring data from #{source}..."
      pg_load_dump source, *pg_get_config.values_at('username', 'database')
      puts 'done'
    end
  end
end
