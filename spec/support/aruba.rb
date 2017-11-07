require 'aruba/rspec'
require 'arel'

module ChronoTest

  module Aruba
    def aruba_working_directory
      File.expand_path("../../#{::Aruba.config.working_directory}", __dir__)
    end

    def dummy_app_directory
      File.expand_path("../../tmp/railsapp/", __dir__)
    end

    def copy_dummy_app_into_aruba_working_directory
      unless File.file?(Pathname.new(dummy_app_directory).join('Rakefile'))
        raise %q(
          The dummy application does not exist
          Run `bundle exec rake testapp:create`
        )
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
  end
end
