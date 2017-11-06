require 'aruba/rspec'
module ChronoTest
  module Aruba
    def aruba_working_directory
      File.expand_path("../../#{::Aruba.config.working_directory}", __dir__)
    end

    def dummy_app_directory
      File.expand_path("../../tmp/dummy_engine/test/dummy", __dir__)
    end

    def copy_dummy_app_into_aruba_working_directory
      unless File.file?(Pathname.new(dummy_app_directory).join('Rakefile'))
        raise %q(
          The dummy application does not exist
          Run `bundle exec rake dummy:create`
        )
      end
      FileUtils.cp_r(Dir.glob("#{dummy_app_directory}/*"), aruba_working_directory)
    end
  end
end


