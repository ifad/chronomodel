require 'aruba/rspec'
module ChronoTest
  module Aruba
    def aruba_working_directory
      File.expand_path("../../#{::Aruba.config.working_directory}", __dir__)
    end

    def dummy_app_directory
      File.expand_path("../dummy", __dir__)
    end
  end
end
