# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'database migrations', type: :aruba do
  before { copy_db_config }

  context 'when a migration is generated' do
    before { run_command_and_stop('bundle exec rails g migration CreateModels name:string') }

    describe 'bundle exec rails db:migrate' do
      subject { action && last_command_started }

      let(:action) { run_command('bundle exec rails db:migrate') }

      it { is_expected.to be_successfully_executed }
      it { is_expected.to have_output(/CreateModels: migrated/) }
    end
  end

  describe 'rerun bundle exec rails db:drop db:create db:migrate', issue: 56 do
    subject { action && last_command_started }

    let(:command) { 'bundle exec rails db:drop db:create db:migrate' }
    let(:action) { run_command(command) }
    let(:regex) { /-- change_table\(:impressions, {:temporal=>true, :copy_data=>true}\)/ }

    before { copy('%/migrations/56/', 'db/migrate') }

    describe 'once' do
      it { is_expected.to be_successfully_executed }
      it { is_expected.to have_output(regex) }
    end

    describe 'twice' do
      before do
        action
      end

      it { is_expected.to be_successfully_executed }
      it { is_expected.to have_output(regex) }
    end
  end
end
