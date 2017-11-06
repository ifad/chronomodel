require 'spec_helper'

describe 'rake tasks' do
  before { FileUtils.cp_r(Dir.glob("#{dummy_app_directory}/*"), aruba_working_directory) }

  describe 'rake -T', type: :aruba do
    before { run_simple('rake -T') }
    subject { last_command_started.output }
    it { is_expected.to include('db:structure:load') }
    it { is_expected.to include('db:schema:load') }
  end
end
