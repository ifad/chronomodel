require 'spec_helper'

describe 'rake tasks' do
  before { copy_dummy_app_into_aruba_working_directory }

  describe 'rake -T', type: :aruba do
    before { run_simple('rake -T') }
    subject { last_command_started.output }
    it { is_expected.to include('db:structure:load') }
    it { is_expected.to include('db:schema:load') }
  end
end
