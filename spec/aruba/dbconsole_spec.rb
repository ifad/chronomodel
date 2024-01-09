# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'rails dbconsole', type: :aruba do
  let(:action) { run_command("bash -c \"echo 'select 1 as foo_column; \\q' | bundle exec rails db\"") }
  let(:last_command) { action && last_command_started }

  before { copy_db_config }

  it { expect(last_command).to be_successfully_executed }
  it { expect(last_command).to have_output(/\bfoo_column\b/) }
end
