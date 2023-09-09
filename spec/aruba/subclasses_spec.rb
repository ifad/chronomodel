# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'subclasses spec', type: :aruba do
  let(:action) { run_command('bundle exec rails runner "Foo.subclasses"') }
  let(:last_command) { action && last_command_started }

  before do
    set_environment_variable 'CM_TEST_EAGER_LOAD', true
    set_environment_variable 'CM_TEST_CACHE_CLASSES', true
    copy_db_config
    write_file(
      'app/models/foo.rb',
      'class Foo < ApplicationRecord; include ChronoModel::TimeMachine; end;'
    )
  end

  it 'does not break when eager loading and caching classes' do
    expect(last_command).to be_successfully_executed
  end
end
