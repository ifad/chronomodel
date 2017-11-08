require 'spec_helper'

describe 'database migrations' do
  context 'after a migration was generated' do
    before { write_file('config/database.yml',
      File.read(File.expand_path('fixtures/database_without_username_and_password.yml', __dir__))) }

    before { run_simple('bundle exec rails g migration CreateModels name:string') }

    describe 'bundle exec rake db:migrate', :announce_stdout, :announce_stderr, type: :aruba do
      let(:action) { run('bundle exec rake db:migrate') }
      let(:last_command) { action && last_command_started }

      specify { expect(last_command).to be_successfully_executed }
      specify { expect(last_command).to have_output(/CreateModels: migrated/) }
    end
  end
end
