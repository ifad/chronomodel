# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'rails dbconsole', type: :aruba do
  subject { action && last_command_started }

  let(:action) { run_command("bash -c \"echo 'select 1 as foo_column; \\q' | bundle exec rails db\"") }

  before { copy_db_config }

  it { is_expected.to be_successfully_executed }
  it { is_expected.to have_output(/\bfoo_column\b/) }
end
