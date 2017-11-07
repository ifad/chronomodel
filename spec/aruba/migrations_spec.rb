require 'spec_helper'

describe 'database migrations' do
  context 'after a migration was generated' do
    before { run_simple('bundle exec rails g migration CreateModels name:string') }

    describe 'bundle exec rails db:migrate', type: :aruba do
      before { run('bundle exec rails db:migrate') }
      subject { last_command_started }
      it { is_expected.to be_successfully_executed }
      it { is_expected.to have_output /CreateModels: migrated/ }
    end
  end
end
