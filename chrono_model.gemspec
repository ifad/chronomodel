# -*- encoding: utf-8 -*-
require File.expand_path('../lib/chrono_model/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ['Marcello Barnaba', 'Peter Joseph Brindisi']
  gem.email         = ['vjt@openssl.it', 'p.brindisi@ifad.org']
  gem.description   = %q{Give your models as-of date temporal extensions. Built entirely for PostgreSQL >= 9.0}
  gem.summary       = %q{Temporal extensions (SCD Type II) for Active Record}
  gem.homepage      = 'http://github.com/ifad/chronomodel'

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = "chrono_model"
  gem.require_paths = ["lib"]
  gem.version       = ChronoModel::VERSION

  gem.add_dependency "activerecord", "~> 4.0"
  gem.add_dependency "pg"
  gem.add_dependency "multi_json"
end
