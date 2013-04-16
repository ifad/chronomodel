# h/t http://stackoverflow.com/questions/4698467
#
Rails.application.config.active_record.schema_format = :sql

# Clear Rails' ones
%w( db:structure:dump db:structure:load ).each {|t| Rake::Task[t].clear }

# Make schema:dump and schema:load invoke structure:dump and structure:load
Rake::Task['db:schema:dump'].clear.enhance(['environment']) do
  Rake::Task['db:structure:dump'].invoke
end

Rake::Task['db:schema:load'].clear.enhance(['environment']) do
  Rake::Task['db:structure:load'].invoke
end

# PG utilities
#
module PG
  extend self

  def config!
    ActiveRecord::Base.connection_pool.spec.config.tap do |config|
      ENV['PGHOST']     = config[:host].to_s     if config.key?(:host)
      ENV['PGPORT']     = config[:port].to_s     if config.key?(:port)
      ENV['PGPASSWORD'] = config[:password].to_s if config.key?(:password)
    end
  end

  def make_dump(target, username, database, *options)
    exec 'pg_dump', '-f', target, '-U', username, database, *options
  end

  def load_dump(source, username, database, *options)
    exec 'psql', '-U', username, '-f', source, database, *options
  end

  def exec(*argv)
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

  def logger
    ActiveRecord::Base.logger
  end

end
