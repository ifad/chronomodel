require 'spec_helper'

describe 'rake tasks', type: :aruba do
  describe 'bundle exec rake -T' do
    before { run_simple('bundle exec rake -T') }
    subject { last_command_started }
    it { is_expected.to have_output(/db:structure:load/) }
  end


  context 'given a file db/structure.sql' do
    let(:content) { File.read(File.expand_path('migrations/structure.sql', __dir__)) }
    before { write_file('db/structure.sql', content) }

    describe 'db:structure:load' do
      before { run_simple('bundle exec rake db:structure:load') }
      subject { last_command_started }

      it { is_expected.to be_successfully_executed }
      it { is_expected.to have_output /exit 0/ }
    end
  end
end
