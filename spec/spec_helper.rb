# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
#
require 'simplecov'
SimpleCov.start

require 'chrono_model'

require 'support/connection'
require 'support/matchers/schema'
require 'support/matchers/table'
require 'support/matchers/column'
require 'support/matchers/index'
require 'support/aruba'

# Rails 5 returns a True/FalseClass
AR_TRUE, AR_FALSE  = ActiveRecord::VERSION::MAJOR == 4 ? ['t', 'f'] : [true, false]

RSpec.configure do |config|
  config.include(ChronoTest::Matchers::Schema)
  config.include(ChronoTest::Matchers::Table)
  config.include(ChronoTest::Matchers::Column)
  config.include(ChronoTest::Matchers::Index)
  config.include(ChronoTest::Aruba, type: :aruba)

  ChronoTest.recreate_database!
end
