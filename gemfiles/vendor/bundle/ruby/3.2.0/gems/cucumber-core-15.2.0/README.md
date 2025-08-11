<img src=".github/img/logo.svg" alt="" width="75" />

# Cucumber

[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://vshymanskyy.github.io/StandWithUkraine)
[![OpenCollective](https://opencollective.com/cucumber/backers/badge.svg)](https://opencollective.com/cucumber)
[![OpenCollective](https://opencollective.com/cucumber/sponsors/badge.svg)](https://opencollective.com/cucumber)
[![Test cucumber-core](https://github.com/cucumber/cucumber-ruby-core/actions/workflows/test.yml/badge.svg)](https://github.com/cucumber/cucumber-ruby-core/actions/workflows/test.yml)
[![Code Climate](https://codeclimate.com/github/cucumber/cucumber-ruby-core.svg)](https://codeclimate.com/github/cucumber/cucumber-ruby-core)

Cucumber is a tool for running automated tests written in plain language. Because they're
written in plain language, they can be read by anyone on your team. Because they can be
read by anyone, you can use them to help improve communication, collaboration and trust on
your team.

<img src="./.github/img/gherkin-example.png" alt="Cucumber Gherkin Example" width="728" />

Cucumber Core is the [inner hexagon](https://en.wikipedia.org/wiki/Hexagonal_architecture_(software))
for the [Ruby flavour of Cucumber](https://github.com/cucumber/cucumber-ruby).

It contains the core domain logic to execute Cucumber features. It has no user interface,
just a Ruby API. If you're interested in how Cucumber works, or in building other
tools that work with Gherkin documents, you've come to the right place.

See [CONTRIBUTING.md](CONTRIBUTING.md) for info on contributing to Cucumber (issues,
PRs, etc.).

Everyone interacting in this codebase and issue tracker is expected to follow the
Cucumber [code of conduct](https://cucumber.io/conduct).

## Installation

`cucumber-core` is a Ruby gem. Install it as you would install any gem: add
`cucumber-core` to your Gemfile:

    gem 'cucumber-core'

then install it:

    $ bundle

or install the gem directly:

    $ gem install cucumber-core

### Supported platforms

- Ruby 3.3
- Ruby 3.2
- Ruby 3.1
- Ruby 3.0
- JRuby 9.4 (with [some limitations](https://github.com/cucumber/cucumber-ruby/blob/main/docs/jruby-limitations.md))

## Usage

The following example aims to illustrate how to use `cucumber-core` gem and to
make sure it is working well within your environment. For more details
explanation on what it actually does and how to work with it, see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```ruby
# cucumber_core_example.rb

require 'cucumber/core'
require 'cucumber/core/filter'

class ActivateSteps < Cucumber::Core::Filter.new
  def test_case(test_case)
    test_steps = test_case.test_steps.map do |step|
      step.with_action { print "processing: " }
    end

    test_case.with_steps(test_steps).describe_to(receiver)
  end
end

feature = Cucumber::Core::Gherkin::Document.new(__FILE__, <<-GHERKIN)
Feature:
  Scenario:
    Given some requirements
    When we do something
    Then it should pass
GHERKIN

class MyRunner
  include Cucumber::Core
end

MyRunner.new.execute([feature], [ActivateSteps.new]) do |events|
  events.on(:test_step_finished) do |event|
    test_step, result = event.test_step, event.result
    print "#{test_step.text} #{result}\n"
  end
end
```

If you run this Ruby script:

```shell
ruby cucumber_core_example.rb
```

You should see the following output:

```
processing: some requirements ✓
processing: we do something ✓
processing: it should pass ✓
```

## Documentation and support

- Getting started with Cucumber, writing features, step definitions, and more: https://cucumber.io/docs
- Discord ([invite link here](https://cucumber.io/docs/community/get-in-touch/#discord))
- `cucumber-core` overview: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- How to work with local repositories for `cucumber-gherkin`, `cucumber-messages` or `cucumber-ruby`: [CONTRIBUTING.md#working-with-local-cucumber-dependencies](./CONTRIBUTING.md#working-with-local-cucumber-dependencies)

## Copyright

Copyright (c) Cucumber Ltd. and Contributors. See LICENSE for details.
