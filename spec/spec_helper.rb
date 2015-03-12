# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
#
require 'codeclimate-test-reporter'
CodeClimate::TestReporter.start

require 'chrono_model'

require 'support/connection'
require 'support/matchers/schema'
require 'support/matchers/table'
require 'support/matchers/column'
require 'support/matchers/index'

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true

  config.include(ChronoTest::Matchers::Schema)
  config.include(ChronoTest::Matchers::Table)
  config.include(ChronoTest::Matchers::Column)
  config.include(ChronoTest::Matchers::Index)

  ChronoTest.recreate_database!
end
