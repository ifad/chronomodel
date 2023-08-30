require 'spec_helper'

RSpec.describe 'database migrations', type: :aruba do
  before { copy_db_config }

  context 'after a migration was generated' do
    before { run_command_and_stop('bundle exec rails g migration CreateModels name:string') }

    describe 'bundle exec rake db:migrate' do
      let(:action) { run_command('bundle exec rake db:migrate') }
      let(:last_command) { action && last_command_started }

      it { expect(last_command).to be_successfully_executed }
      it { expect(last_command).to have_output(/CreateModels: migrated/) }
    end
  end

  describe 'rerun bundle exec rake db:drop db:create db:migrate', issue: 56 do
    let(:command) { 'bundle exec rake db:drop db:create db:migrate' }
    before { copy('%/migrations/56/', 'db/migrate') }

    let(:action) { run_command(command) }
    let(:regex) { /-- change_table\(:impressions, {:temporal=>true, :copy_data=>true}\)/ }

    describe 'once' do
      let(:last_command) { action && last_command_started }
      it { expect(last_command).to be_successfully_executed }
      it { expect(last_command).to have_output(regex) }
    end

    describe 'twice' do
      let(:last_command) { run_command_and_stop(command) && action && last_command_started }
      it { expect(last_command).to be_successfully_executed }
      it { expect(last_command).to have_output(regex) }
    end
  end
end
