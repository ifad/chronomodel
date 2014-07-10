require 'shellwords'
load File.expand_path(File.dirname(__FILE__) + '/schema_format.rb')

namespace :db do
  namespace :structure do
    desc "desc 'Dump the database structure to db/structure.sql. Specify another file with DB_STRUCTURE=db/my_structure.sql"
    task :dump => :environment do
      config = PG.config!
      target = ENV['DB_STRUCTURE'] || Rails.root.join('db', 'structure.sql')
      schema_search_path = config[:schema_search_path]

      unless schema_search_path.blank?
        # add in chronomodel schemas
        schema_search_path << ",#{ChronoModel::Adapter::TEMPORAL_SCHEMA}"
        schema_search_path << ",#{ChronoModel::Adapter::HISTORY_SCHEMA}"

        # convert to command line arguments
        schema_search_path = schema_search_path.split(",").map{|part| "--schema=#{Shellwords.escape(part.strip)}" }.join(" ")
      end

      PG.make_dump target,
                   *config.values_at(:username, :database),
                   '-i', '-x', '-s', '-O', schema_search_path

      # Add migration information, after resetting the schema to the default one
      File.open(target, 'a') do |f|
        f.puts "SET search_path TO #{ActiveRecord::Base.connection.schema_search_path};\n\n"
        f.puts ActiveRecord::Base.connection.dump_schema_information
      end

      # the structure.sql file will contain CREATE SCHEMA statements
      # but chronomodel creates the temporal and history schemas
      # when the connection is established, so a db:structure:load fails
      # fix up create schema statements to include the IF NOT EXISTS directive

      sql = File.read(target)
      sql.gsub!(/CREATE SCHEMA /, 'CREATE SCHEMA IF NOT EXISTS ')
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
