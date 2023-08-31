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
    options = %w[
      --skip-action-cable
      --skip-action-mailer
      --skip-action-text
      --skip-active-storage
      --skip-asset-pipeline
      --skip-bundle
      --skip-git
      --skip-javascript
      --skip-sprockets
      --skip-webpack-install
    ]
    FileUtils.mkdir_p('tmp/aruba')
    Dir.chdir('tmp') do
      FileUtils.rm_rf('railsapp')
      sh "rails new railsapp #{options.join(' ')}"
    end
    FileUtils.cp_r('spec/fixtures/railsapp/.', 'tmp/railsapp/')
    FileUtils.rm('tmp/railsapp/Gemfile')
  end
end
