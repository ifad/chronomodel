load File.expand_path(File.dirname(__FILE__) + '/schema_format.rb')

namespace :db do
  namespace :structure do
    desc "desc 'Dump the database structure to db/structure.sql. Specify another file with DB_STRUCTURE=db/my_structure.sql"
    task :dump => :environment do
      config = PG.config!
      target = ENV['DB_STRUCTURE'] || Rails.root.join('db', 'structure.sql')
      schema = config[:schema_search_path]

      if schema.present?
        # If a schema search path is configured, add also the ChronoModel schemas to the dump.
        #
        schema = schema.split /\s*,\s*/
        schema = schema.concat [ ChronoModel::Adapter::TEMPORAL_SCHEMA, ChronoModel::Adapter::HISTORY_SCHEMA ]
        schema = schema.map {|name| "--schema=#{name}" }
      else
        schema = [ ]
      end
      
      PG.make_dump target,
                   *config.values_at(:username, :database),
                   '-x', '-s', '-O', *schema

      # Add migration information, after resetting the schema to the default one
      File.open(target, 'a') do |f|
        f.puts "SET search_path TO #{ActiveRecord::Base.connection.schema_search_path};\n\n"
        f.puts ActiveRecord::Base.connection.dump_schema_information
      end

      # The structure.sql includes CREATE SCHEMA statements, but as these are executed
      # when the connection to the database is established, a db:structure:load fails.
      # This code adds the IF NOT EXISTS clause to CREATE SCHEMA statements as long as
      # it is not already present.
      #
      sql = File.read(target)
      sql.gsub!(/CREATE SCHEMA (?!IF NOT EXISTS)/, '\&IF NOT EXISTS ')
      File.open(target, "w") { |file| file << sql  }
    end

    desc "Load structure.sql file into the current environment's database"
    task :load => :environment do
      # Loads the db/structure.sql file into current environment's database.
      #
      source = ENV['DB_STRUCTURE'] || Rails.root.join('db', 'structure.sql')

      PG.load_dump source, *PG.config!.values_at(:username, :database, :template)
    end
  end

  namespace :data do
    desc "Save a dump of the database in ENV['DUMP'] or db/data.NOW.sql"
    task :dump => :environment do
      target = ENV['DUMP'] || Rails.root.join('db', "data.#{Time.now.to_f}.sql")

      PG.make_dump target, *PG.config!.values_at(:username, :database), '-c'
    end

    desc "Load a dump of the database from ENV['DUMP']"
    task :load => :environment do
      source = ENV['DUMP'].presence or
        raise ArgumentError, "Invoke as rake db:data:load DUMP=/path/to/data.sql"

      PG.load_dump source, *PG.config!.values_at(:username, :database)
    end
  end
end
