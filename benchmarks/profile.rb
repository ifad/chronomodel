#!/usr/bin/env ruby -s

# frozen_string_literal: true

require_relative 'benchmark_sample'
require 'ruby-prof'

result = RubyProf::Profile.profile do
  run_benchmark_sample
end

printer = RubyProf::FlatPrinter.new(result)
printer.print($stdout, {})
