require 'spec_helper'

describe 'database migrations', type: :aruba do
  context 'after a migration was generated' do
    before { write_file('config/database.yml',
      File.read(File.expand_path('fixtures/database_without_username_and_password.yml', __dir__))) }

    before { run_command_and_stop('bundle exec rails g migration CreateModels name:string') }

    describe 'bundle exec rake db:migrate' do
      let(:action) { run_command('bundle exec rake db:migrate') }
      let(:last_command) { action && last_command_started }

      specify { expect(last_command).to be_successfully_executed }
      specify { expect(last_command).to have_output(/CreateModels: migrated/) }
    end
  end

  describe 'rerun bundle exec rake db:drop db:create db:migrate', issue: 56 do
    let(:command) { 'bundle exec rake db:drop db:create db:migrate' }
    before do
      copy(
        '../../spec/aruba/fixtures/database_without_username_and_password.yml',
        'config/database.yml'
      )
      copy(
        '../../spec/aruba/fixtures/migrations/56/',
        'db/migrate'
      )
    end

    let(:action) { run_command(command) }
    let(:regex) { /-- change_table\(:impressions, {:temporal=>true, :copy_data=>true}\)/ }

    describe 'once' do
      let(:last_command) { action && last_command_started }
      specify { expect(last_command).to be_successfully_executed }
      specify { expect(last_command).to have_output(regex) }
    end

    describe 'twice' do
      let(:last_command) { run_command_and_stop(command) && action && last_command_started }
      specify { expect(last_command).to be_successfully_executed }
      specify { expect(last_command).to have_output(regex) }
    end
  end
end
