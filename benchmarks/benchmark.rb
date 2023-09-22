#!/usr/bin/env ruby -s

# frozen_string_literal: true

unless ENV['COVERAGE'].nil?
  require 'simplecov'

  SimpleCov.start
  SimpleCov.command_name 'Bench'
end

require_relative 'benchmark_sample'
require 'benchmark'

ITERATIONS = 5_000

Foo.create! name: 'My Foo'
Bar.create! name: 'My Bar'

first_foo = Foo.first

Benchmark.bmbm(30) do |x|
  x.report('.merge') do
    ITERATIONS.times { Foo.merge(Foo.all) }
  end

  x.report('.first') do
    ITERATIONS.times { Foo.first }
  end

  x.report('.last') do
    ITERATIONS.times { Foo.last }
  end

  x.report('.as_of.first') do
    ITERATIONS.times { Foo.as_of(Time.now).first }
  end

  x.report('History.merge') do
    ITERATIONS.times { Foo::History.merge(Foo::History.all) }
  end

  x.report('History.first') do
    ITERATIONS.times { Foo::History.first }
  end

  x.report('History.last') do
    ITERATIONS.times { Foo::History.last }
  end

  x.report('#history.first') do
    ITERATIONS.times { first_foo.history.first }
  end

  x.report('#history.last') do
    ITERATIONS.times { first_foo.history.last }
  end

  x.report('#as_of') do
    ITERATIONS.times { first_foo.as_of(Time.now) }
  end

  x.report('#timeline') do
    ITERATIONS.times { first_foo.timeline }
  end

  x.report('TimeGate .merge') do
    ITERATIONS.times { Bar.merge(Bar.all) }
  end

  x.report('TimeGate .first') do
    ITERATIONS.times { Bar.first }
  end

  x.report('TimeGate .last') do
    ITERATIONS.times { Bar.last }
  end
end
