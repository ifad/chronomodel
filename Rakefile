require "bundler/gem_tasks"

# RSpec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new do |spec|
  spec.rspec_opts = '-f doc'
end
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
      sh 'rails new railsapp --skip-bundle --skip-javascript --skip-webpack-install --skip-git'
    end
    FileUtils.cp_r('spec/fixtures/railsapp/.', 'tmp/railsapp/')
    FileUtils.rm('tmp/railsapp/Gemfile')
  end
end
