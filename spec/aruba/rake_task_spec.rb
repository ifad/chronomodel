require 'spec_helper'

describe 'rake tasks', type: :aruba do
  describe 'bundle exec rake -T' do
    before { run_simple('bundle exec rake -T') }
    subject { last_command_started }
    it { is_expected.to have_output(/db:structure:load/) }
  end

  describe 'db:structure:load' do
    let(:action) { run('bundle exec rails db:structure:load') }
    let(:last_command) { action && last_command_started }

    context 'given a file db/structure.sql' do
      let(:structure_sql) { File.read(File.expand_path('fixtures/empty_structure.sql', __dir__)) }
      before { write_file('db/structure.sql', structure_sql) }

      specify { expect(last_command).to be_successfully_executed }

      context 'without a specified username and password', issue: 55 do
        let(:database_yml) { File.read(File.expand_path('fixtures/database_without_username_and_password.yml', __dir__)) }
        before { write_file('config/database.yml', database_yml) }
        specify { expect(last_command).to be_successfully_executed }
      end
    end
  end
end
