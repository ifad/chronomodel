# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
#
require 'simplecov'
SimpleCov.start

require 'byebug'

require 'chrono_model'

require 'support/connection'
require 'support/matchers/schema'
require 'support/matchers/table'
require 'support/matchers/column'
require 'support/matchers/index'
require 'support/matchers/function'
require 'support/aruba'

puts "Testing against Active Record #{ActiveRecord::VERSION::STRING} with Arel #{Arel::VERSION}"

# Rails 5 returns a True/FalseClass
AR_TRUE, AR_FALSE  = ActiveRecord::VERSION::MAJOR == 4 ? ['t', 'f'] : [true, false]

RSpec.configure do |config|
  config.include(ChronoTest::Matchers::Schema)
  config.include(ChronoTest::Matchers::Table)
  config.include(ChronoTest::Matchers::Column)
  config.include(ChronoTest::Matchers::Index)
  config.include(ChronoTest::Aruba, type: :aruba)

  ChronoTest.recreate_database!

  config.before(:example, type: :aruba) do
    copy_dummy_app_into_aruba_working_directory
    recreate_railsapp_database
  end
end
