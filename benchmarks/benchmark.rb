#!/usr/bin/env ruby -s

# frozen_string_literal: true

require_relative 'benchmark_sample'
require 'benchmark'

Benchmark.bmbm(30) do |x|
  x.report('benchmark_sample') do
    run_benchmark_sample
  end
end
