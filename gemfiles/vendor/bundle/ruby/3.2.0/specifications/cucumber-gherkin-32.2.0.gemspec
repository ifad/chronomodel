# -*- encoding: utf-8 -*-
# stub: cucumber-gherkin 32.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "cucumber-gherkin".freeze
  s.version = "32.2.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 3.2.8".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/cucumber/gherkin/issues", "changelog_uri" => "https://github.com/cucumber/gherkin/blob/main/CHANGELOG.md", "documentation_uri" => "https://cucumber.io/docs/gherkin/", "mailing_list_uri" => "https://groups.google.com/forum/#!forum/cukes", "source_code_uri" => "https://github.com/cucumber/gherkin/blob/main/ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["G\u00E1sp\u00E1r Nagy".freeze, "Aslak Helles\u00F8y".freeze, "Steve Tooke".freeze]
  s.date = "1980-01-02"
  s.description = "Gherkin parser".freeze
  s.email = "cukes@googlegroups.com".freeze
  s.executables = ["gherkin".freeze, "gherkin-ruby".freeze]
  s.files = ["bin/gherkin".freeze, "bin/gherkin-ruby".freeze]
  s.homepage = "https://github.com/cucumber/gherkin".freeze
  s.licenses = ["MIT".freeze]
  s.rdoc_options = ["--charset=UTF-8".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.2".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "cucumber-gherkin-32.2.0".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<cucumber-messages>.freeze, ["> 25", "< 28"])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.1"])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.13"])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 1.71.2"])
  s.add_development_dependency(%q<rubocop-rspec>.freeze, ["~> 3.4.0"])
  s.add_development_dependency(%q<rubocop-packaging>.freeze, ["~> 0.5.2"])
  s.add_development_dependency(%q<rubocop-performance>.freeze, ["~> 1.23.1"])
  s.add_development_dependency(%q<rubocop-rake>.freeze, ["~> 0.6.0"])
end
