# frozen_string_literal: true

require 'spec_helper'
require 'rake'

RSpec.describe 'rake tasks', type: :aruba do
  describe 'bundle exec rake -T' do
    subject { last_command_started }

    before do
      copy_db_config
      run_command_and_stop('bundle exec rake -T')
    end

    it { is_expected.to have_output(schema_load_task(as_regexp: true)) }
  end

  describe 'db:schema:dump' do
    subject { last_command_started }

    let(:db_file) { 'db/test.sql' }

    before do
      copy_db_config
      run_command_and_stop("bundle exec rails #{schema_dump_task} SCHEMA=db/test.sql")
    end

    it { is_expected.to be_successfully_executed }
    it { expect(db_file).to be_an_existing_file }
    it { expect(db_file).not_to have_file_content(/\A--/) }

    context 'with schema_search_path option' do
      before do
        copy_db_config('database_with_schema_search_path.yml')
        run_command_and_stop("bundle exec rails #{schema_dump_task} SCHEMA=db/test.sql")
      end

      it 'includes chronomodel schemas' do
        expect(db_file).to have_file_content(/^CREATE SCHEMA IF NOT EXISTS history;$/)
          .and have_file_content(/^CREATE SCHEMA IF NOT EXISTS temporal;$/)
          .and have_file_content(/^CREATE SCHEMA IF NOT EXISTS public;$/)
      end
    end
  end

  describe 'db:schema:load' do
    subject { action && last_command_started }

    let(:action) { run_command("bundle exec rails #{schema_load_task}") }

    context 'with file argument' do
      let(:action) { run_command_and_stop("bundle exec rails #{schema_load_task} SCHEMA=db/test.sql") }

      before do
        copy_db_config
        copy('%/set_config.sql', 'db/test.sql')
      end

      it { is_expected.to be_successfully_executed }
    end

    context 'with db/structure.sql' do
      before do
        copy('%/empty_structure.sql', 'db/structure.sql')
      end

      context 'with default username and password', issue: 55 do
        before do
          copy_db_config('database_with_default_username_and_password.yml')

          # Handle Homebrew on MacOS, whose database superuser name is
          # equal to the name of the current user.
          if which 'brew'
            file_mangle!('config/database.yml') do |contents|
              contents.sub('username: postgres', "username: #{Etc.getlogin}")
            end
          end

          # Handle GitHub Actions
          if ENV['CI']
            file_mangle!('config/database.yml') do |contents|
              contents.sub('username: postgres', 'username: runner')
            end
          end
        end

        it { is_expected.to be_successfully_executed }
      end

      context 'without a specified username and password', issue: 55 do
        before { copy_db_config }

        it { is_expected.to be_successfully_executed }
      end
    end
  end

  describe 'db:data:dump' do
    before do
      copy_db_config
      copy('%/set_config.sql', 'db/test.sql')
      run_command_and_stop('bundle exec rails db:data:dump DUMP=db/test.sql')
    end

    it { expect(last_command_started).to be_successfully_executed }
    it { expect('db/test.sql').to be_an_existing_file }
  end

  describe 'db:data:load' do
    before do
      copy_db_config
      copy('%/empty_structure.sql', 'db/test.sql')
      run_command_and_stop('bundle exec rails db:data:load DUMP=db/test.sql')
    end

    it { expect(last_command_started).to be_successfully_executed }
  end
end
