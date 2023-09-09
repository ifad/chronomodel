# frozen_string_literal: true

# The db consle does not work on Rails 5.0
#
unless Bundler.default_gemfile.to_s =~ /rails_5.0/

  require 'spec_helper'

  RSpec.describe 'rails dbconsole' do
    before { copy_db_config }

    describe 'rails dbconsole', type: :aruba do
      let(:action) { run_command("bash -c \"echo 'select 1 as foo_column; \\q' | bundle exec rails db\"") }
      let(:last_command) { action && last_command_started }

      it { expect(last_command).to be_successfully_executed }
      it { expect(last_command).to have_output(/\bfoo_column\b/) }
    end
  end

end
