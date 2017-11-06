#!/usr/bin/env rake
require "bundler/gem_tasks"

# RSpec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new
task :default => :spec


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
      application_config_path = 'dummy_engine/test/dummy/config/application.rb'
      content = File.read(application_config_path)
      File.open(application_config_path, "w") do |f|
        f.write(content.gsub('dummy_engine', 'chrono_model'))
      end

    end
  end
end
