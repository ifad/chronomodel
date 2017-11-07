#!/usr/bin/env rake
require "bundler/gem_tasks"

# RSpec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new
task :default => ['dummy:create', :spec]


namespace :dummy do
  desc 'Create a dummy rails application for testing in /tmp'
  task :create do
    FileUtils.mkdir_p('tmp/aruba')
    Dir.chdir('tmp') do
      FileUtils.rm_rf('railsapp')
      sh 'rails new railsapp --skip-bundle'
    end
    FileUtils.cp_r('overwrite/.', 'tmp/railsapp/')
    FileUtils.rm('tmp/railsapp/Gemfile')
  end
end
