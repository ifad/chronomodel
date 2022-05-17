# frozen_string_literal: true

require File.expand_path('lib/chrono_model/version', __dir__)

Gem::Specification.new do |gem|
  gem.authors       = ['Marcello Barnaba', 'Peter Joseph Brindisi']
  gem.email         = ['vjt@openssl.it', 'p.brindisi@ifad.org']
  gem.description   = 'Give your models as-of date temporal extensions. Built entirely for PostgreSQL >= 9.4'
  gem.summary       = 'Temporal extensions (SCD Type II) for Active Record'
  gem.homepage      = 'https://github.com/ifad/chronomodel'

  gem.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = 'chrono_model'
  gem.license       = 'MIT'
  gem.require_paths = ['lib']
  gem.version       = ChronoModel::VERSION

  gem.metadata = {
    'bug_tracker_uri' => 'https://github.com/ifad/chronomodel/issues',
    'homepage_uri' => 'https://github.com/ifad/chronomodel',
    'source_code_uri' => 'https://github.com/ifad/chronomodel'
  }

  gem.required_ruby_version = '>= 2.2.2'

  gem.add_dependency 'activerecord', '>= 5.0'
  gem.add_dependency 'multi_json'
  gem.add_dependency 'pg', '> 1.1'

  gem.add_development_dependency 'aruba'
  gem.add_development_dependency 'byebug'
  gem.add_development_dependency 'fuubar'
  gem.add_development_dependency 'hirb'
  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'rails'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'simplecov'
end
