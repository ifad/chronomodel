#!/usr/bin/env ruby -s

# frozen_string_literal: true

require_relative 'benchmark_sample'
require 'memory_profiler'

MemoryProfiler.report(allow_files: 'chronomodel/lib') do
  run_benchmark_sample
end.pretty_print
