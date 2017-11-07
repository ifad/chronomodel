require 'spec_helper'

describe 'database migrations' do
  context 'after a migration was generated' do
    before { run_simple('bundle exec rails g migration CreateModels name:string') }

    describe 'bundle exec rails db:migrate', type: :aruba do
      let(:action) { run('bundle exec rails db:migrate') }
      let(:last_command) { action && last_command_started }

      specify { expect(last_command).to be_successfully_executed }
      specify { expect(last_command).to have_output /CreateModels: migrated/ }

      context 'without a specified username and password', issue: 55 do
        let(:content) { File.read(File.expand_path('fixtures/database_without_username_and_password.yml', __dir__)) }
        before { write_file('config/database.yml', content) }
        specify { expect(last_command).to be_successfully_executed }
        specify { expect(last_command).to have_output /CreateModels: migrated/ }
      end
    end
  end
end
