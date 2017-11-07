#!/usr/bin/env rake
require "bundler/gem_tasks"

# RSpec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new
task :default => :spec


# Source: https://stackoverflow.com/a/3273394/2069431
def find_and_replace(dir)
  Dir.glob(dir + '/*.rb').each do |name|
    new_content = File.read(name)
      .gsub('mount DummyEngine::Engine => "/dummy_engine"', '')
      .gsub('dummy_engine', 'chrono_model')
    File.write(name, new_content)
  end
  Dir.glob(dir + '/*/').each(&method(:find_and_replace))
end

namespace :dummy do
  desc 'Create a dummy rails application for testing in /tmp'
  task :create do
    FileUtils.mkdir_p('tmp/aruba')
    Dir.chdir('tmp') do
      FileUtils.rm_rf('dummy_engine')

      # Create a new rails engine
      # http://guides.rubyonrails.org/engines.html#generating-an-engine
      sh 'rails plugin new dummy_engine --mountable'

      # Now require 'chrono_model' instead of 'dummy_engine'.
      # We can't do this just by creating a rails plugin called 'chrono_model'.
      # Rails would complain because of an existing constant 'ChronoModel'.
      find_and_replace('dummy_engine/test/dummy')

    end
    FileUtils.cp('database.yml', 'tmp/dummy_engine/test/dummy/config/')
  end
end
