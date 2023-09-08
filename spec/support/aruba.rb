require 'aruba/rspec'
require 'arel'
require 'rake'
require 'rails'

module ChronoTest
  module Aruba
    def load_schema_task(as_regexp: false)
      str =
        if Rails.version < '7.0'
          'db:structure:load'
        else
          'db:schema:load'
        end
      as_regexp ? Regexp.new(str) : str
    end

    def copy_db_config(file = 'database_without_username_and_password.yml')
      copy("%/#{file}", 'config/database.yml')
    end

    def dump_schema_task(as_regexp: false)
      str =
        if Rails.version < '7.0'
          'db:structure:dump'
        else
          'db:schema:dump'
        end
      as_regexp ? Regexp.new(str) : str
    end

    def aruba_working_directory
      File.expand_path("../../#{::Aruba.config.working_directory}", __dir__)
    end

    def dummy_app_directory
      File.expand_path('../../tmp/railsapp/', __dir__)
    end

    def copy_dummy_app_into_aruba_working_directory
      unless File.file?(Pathname.new(dummy_app_directory).join('Rakefile'))
        raise '
          The dummy application does not exist
          Run `bundle exec rake testapp:create`
        '
      end
      FileUtils.rm_rf(Dir.glob("#{aruba_working_directory}/*"))
      FileUtils.cp_r(Dir.glob("#{dummy_app_directory}/*"), aruba_working_directory)
    end

    def recreate_railsapp_database
      connection = AR.connection # we're still the 'chronomodel' user
      database = 'chronomodel_railsapp'
      connection.drop_database   database
      connection.create_database database
    end

    def file_mangle!(file)
      # Read
      file_contents = read(file).join("\n")

      # Mangle
      file_contents = yield(file_contents)

      # Write
      write_file file, file_contents
    end
  end
end
