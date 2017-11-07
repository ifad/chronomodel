require 'spec_helper'

describe 'rake tasks', type: :aruba do
  describe 'bundle exec rake -T' do
    before { run_simple('bundle exec rake -T') }
    subject { last_command_started }
    it { is_expected.to have_output(/db:structure:load/) }
  end

  describe 'db:structure:load' do
    let(:action) { run('bundle exec rake db:structure:load') }
    let(:last_command) { action && last_command_started }

    context 'given a file db/structure.sql' do
      let(:structure_sql) { 'fixtures/empty_structure.sql' }
      before { write_file('db/structure.sql', File.read(File.expand_path(structure_sql, __dir__))) }
      before { write_file('config/database.yml', File.read(File.expand_path(database_yml, __dir__))) }

      subject { expect(last_command).to be_successfully_executed }

      context 'with default username and password', issue: 55 do
        let(:database_yml) { 'fixtures/database_with_default_username_and_password.yml' }

        specify { subject }
      end

      context 'without a specified username and password', issue: 55 do
        let(:database_yml) { 'fixtures/database_without_username_and_password.yml' }

        specify { subject }
      end
    end
  end
end
