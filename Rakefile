#!/usr/bin/env rake
require "bundler/gem_tasks"

# RSpec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new
task :default => ['testapp:create', :spec]

# Create a test Rails app in tmp/railsapp for testing the rake
# tasks and overall Rails integration with Aruba.
#
namespace :testapp do
  desc 'Create a dummy rails application for testing in /tmp'
  task :create do
    FileUtils.mkdir_p('tmp/aruba')
    Dir.chdir('tmp') do
      FileUtils.rm_rf('railsapp')
      sh 'rails new railsapp --skip-bundle'
    end
    FileUtils.cp_r('spec/aruba/fixtures/railsapp/.', 'tmp/railsapp/')
    FileUtils.rm('tmp/railsapp/Gemfile')
  end
end
