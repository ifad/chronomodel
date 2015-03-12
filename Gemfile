source 'https://rubygems.org'

# Specify your gem's dependencies in chrono_model.gemspec
gemspec

group :development do
  gem 'pry'
  gem 'hirb'

  gem(
    case RUBY_VERSION.to_f
    when 1.8 then 'ruby-debug'
    when 1.9 then 'debugger'
    else          'byebug'
    end
  )
end

group :test do
  gem 'rspec', '~> 2.0'
  gem 'rake'
  gem 'fuubar'
  gem 'codeclimate-test-reporter', require: nil
end
