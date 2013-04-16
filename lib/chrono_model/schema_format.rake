load File.expand_path(File.dirname(__FILE__) + '/schema_format.rb')

namespace :db do
  # Define PG environment utility methods
  task :pg_env => :environment do
    def pg_get_config
      ActiveRecord::Base.connection_pool.spec.config.tap do |config|
        ENV['PGHOST']     = config[:host].to_s     if config.key?(:host)
        ENV['PGPORT']     = config[:port].to_s     if config.key?(:port)
        ENV['PGPASSWORD'] = config[:password].to_s if config.key?(:password)
      end
    end

    def pg_exec(*argv)
      logger = Rails.logger

      argv = argv.compact.map(&:to_s)

      print "> \033[1m#{argv.join(' ')}\033[0m... "
      logger.info "PG: exec #{argv.join(' ')}"

      stdout, stdout_w = IO.pipe
      stderr, stderr_w = IO.pipe
      pid = fork {
        stdout.close; STDOUT.reopen(stdout_w)
        stderr.close; STDERR.reopen(stderr_w)

        Kernel.exec *argv
      }
      stdout_w.close; stderr_w.close
      pid, status = Process.wait2

      puts "exit #{status.exitstatus}"
      logger.info "PG: exit #{status.exitstatus}"

      out, err = stdout.read.chomp, stderr.read.chomp
      stdout.close; stderr.close

      if out.present?
        logger.info "PG: -----8<----- stdout ----->8-----"
        logger.info out
        logger.info "PG: ----8<---- end stdout ---->8----"
      end

      if err.present?
        logger.info "PG: -----8<----- stderr ----->8-----"
        logger.info err
        logger.info "PG: ----8<---- end stderr ---->8----"
      end
    end

    def pg_make_dump(target, username, database, *options)
      pg_exec 'pg_dump', '-f', target, '-U', username, database, *options
    end

    def pg_load_dump(source, username, database, *options)
      pg_exec 'psql', '-U', username, '-f', source, database, *options
    end
  end

  namespace :structure do
    desc "desc 'Dump the database structure to db/structure.sql. Specify another file with DB_STRUCTURE=db/my_structure.sql"
    task :dump => :pg_env do
      target = ENV['DB_STRUCTURE'] || Rails.root.join('db', 'structure.sql')
      schema = pg_get_config[:schema_search_path] || 'public'

      pg_make_dump target, *pg_get_config.values_at(:username, :database),
        '-s', '-O', '-n', schema,
        '-n', ChronoModel::Adapter::TEMPORAL_SCHEMA,
        '-n', ChronoModel::Adapter::HISTORY_SCHEMA

      # Add migration information, after resetting the schema to the default one
      File.open(target, 'a') do |f|
        f.puts "SET search_path = #{schema}, pg_catalog;"
        f.puts ActiveRecord::Base.connection.dump_schema_information
      end
    end


    desc "Load structure.sql file into the current environment's database"
    task :load => :pg_env do
      # Loads the db/structure.sql file into current environment's database.
      #
      source = ENV['DB_STRUCTURE'] || Rails.root.join('db', 'structure.sql')

      pg_load_dump source, *pg_get_config.values_at(:username, :database, :template)
    end
  end

  namespace :data do
    desc "Save a dump of the database in ENV['DUMP'] or db/data.NOW.sql"
    task :dump => :pg_env do
      target = ENV['DUMP'] || Rails.root.join('db', "data.#{Time.now.to_f}.sql")

      pg_make_dump target, *pg_get_config.values_at(:username, :database), '-c'
    end

    desc "Load a dump of the database from ENV['DUMP']"
    task :load => :pg_env do
      source = ENV['DUMP'].presence or
        raise ArgumentError, "Invoke as rake db:data:load DUMP=/path/to/data.sql"

      pg_load_dump source, *pg_get_config.values_at(:username, :database)
    end
  end
end
