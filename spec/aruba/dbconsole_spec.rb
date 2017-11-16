require 'spec_helper'

describe 'rails dbconsole' do
  before do
    write_file(
      'config/database.yml',
      File.read(File.expand_path('fixtures/database_without_username_and_password.yml', __dir__)))
  end

  describe 'rails dbconsole', type: :aruba do
    let(:action) { run_command("bash -c \"echo 'select 1 as foo_column; \\q' | bundle exec rails db\"") }
    let(:last_command) { action && last_command_started }

    specify { expect(last_command).to be_successfully_executed }
    specify { expect(last_command).to have_output(/\bfoo_column\b/) }
  end
end
