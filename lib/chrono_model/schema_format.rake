require 'shellwords'
load File.expand_path(File.dirname(__FILE__) + '/schema_format.rb')

namespace :db do
  namespace :structure do
    desc "desc 'Dump the database structure to db/structure.sql. Specify another file with DB_STRUCTURE=db/my_structure.sql"
    task :dump => :environment do
      config = PG.config!
      target = ENV['DB_STRUCTURE'] || Rails.root.join('db', 'structure.sql')
      schema = config[:schema_search_path] || 'public'

      search_path = schema
      unless search_path.blank?
        search_path = search_path.split(",").map{|part| "--schema=#{Shellwords.escape(part.strip)}" }.join(" ")
      end

      PG.make_dump target, *config.values_at(:username, :database),
        '-i', '-x', '-s', '-O', search_path,
        "--schema=#{Shellwords.escape(ChronoModel::Adapter::TEMPORAL_SCHEMA)}",
        "--schema=#{Shellwords.escape(ChronoModel::Adapter::HISTORY_SCHEMA)}"

      # Add migration information, after resetting the schema to the default one
      File.open(target, 'a') do |f|
        f.puts "SET search_path TO #{ActiveRecord::Base.connection.schema_search_path};\n\n"
        f.puts ActiveRecord::Base.connection.dump_schema_information
      end
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
