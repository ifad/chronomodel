# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
#
require 'chrono_model'

require 'support/connection'

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.before :suite do
    ChronoTest.recreate_database!
  end
end
