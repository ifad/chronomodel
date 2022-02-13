require 'spec_helper'
require 'rake'
include ChronoTest::Aruba
# add :announce_stdout, :announce_stderr, before the type: aruba tag in order
# to see the commmands' stdout and stderr output.
#

describe 'rake tasks', type: :aruba do
  describe 'bundle exec rake -T' do
    before { run_command_and_stop('bundle exec rake -T') }
    subject { last_command_started }

    it { is_expected.to have_output(load_schema_task(as_regexp: true)) }
  end

  describe "#{dump_schema_task}" do
    let(:database_yml) { 'fixtures/database_without_username_and_password.yml' }
    before { write_file('config/database.yml', File.read(File.expand_path(database_yml, __dir__))) }

    before { run_command_and_stop("bundle exec rake #{dump_schema_task} SCHEMA=db/test.sql") }

    it { expect(last_command_started).to be_successfully_executed }
    it { expect('db/test.sql').to be_an_existing_file }
    it { expect('db/test.sql').not_to have_file_content(/\A--/) }

    context 'with schema_search_path option' do
      let(:database_yml) { 'fixtures/database_with_schema_search_path.yml' }

      before { run_command_and_stop("bundle exec rake #{dump_schema_task} SCHEMA=db/test.sql") }

      it 'includes chronomodel schemas' do
        expect('db/test.sql').to have_file_content(/^CREATE SCHEMA IF NOT EXISTS history;$/)
          .and have_file_content(/^CREATE SCHEMA IF NOT EXISTS temporal;$/)
          .and have_file_content(/^CREATE SCHEMA IF NOT EXISTS public;$/)
      end
    end
  end

  describe 'db:schema:load' do
    let(:database_yml) { 'fixtures/database_without_username_and_password.yml' }
    before { write_file('config/database.yml', File.read(File.expand_path(database_yml, __dir__))) }

    let(:structure_sql) { 'fixtures/set_config.sql' }
    before { write_file('db/test.sql', File.read(File.expand_path(structure_sql, __dir__))) }

    before { run_command_and_stop('bundle exec rake db:schema:load SCHEMA=db/test.sql') }

    it { expect(last_command_started).to be_successfully_executed }
    it { expect(last_command_started).to have_output(/set_config/) }
  end

  describe "#{load_schema_task}" do
    let(:action) { run_command("bundle exec rake #{load_schema_task}") }
    let(:last_command) { action && last_command_started }

    context 'given a file db/structure.sql' do
      let(:structure_sql) { 'fixtures/empty_structure.sql' }
      before { write_file('db/structure.sql', File.read(File.expand_path(structure_sql, __dir__))) }
      before { write_file('config/database.yml', File.read(File.expand_path(database_yml, __dir__))) }

      subject { expect(last_command).to be_successfully_executed }

      context 'with default username and password', issue: 55 do
        let(:database_yml) { 'fixtures/database_with_default_username_and_password.yml' }

        # Handle Homebrew on MacOS, whose database superuser name is
        # equal to the name of the current user.
        #
        before do
          if which 'brew'
            file_mangle!('config/database.yml') do |contents|
              contents.sub('username: postgres', "username: #{Etc.getlogin}")
            end
          end
        end

        specify { subject }
      end

      context 'without a specified username and password', issue: 55 do
        let(:database_yml) { 'fixtures/database_without_username_and_password.yml' }

        specify { subject }
      end
    end
  end

  describe 'db:data:dump' do
    let(:database_yml) { 'fixtures/database_without_username_and_password.yml' }
    before { write_file('config/database.yml', File.read(File.expand_path(database_yml, __dir__))) }

    before { run_command_and_stop('bundle exec rake db:data:dump DUMP=db/test.sql') }

    it { expect(last_command_started).to be_successfully_executed }
    it { expect('db/test.sql').to be_an_existing_file }
  end

  describe 'db:data:load' do
    let(:database_yml) { 'fixtures/database_without_username_and_password.yml' }
    before { write_file('config/database.yml', File.read(File.expand_path(database_yml, __dir__))) }

    let(:structure_sql) { 'fixtures/empty_structure.sql' }
    before { write_file('db/test.sql', File.read(File.expand_path(structure_sql, __dir__))) }

    before { run_command_and_stop('bundle exec rake db:data:load DUMP=db/test.sql') }

    it { expect(last_command_started).to be_successfully_executed }
  end
end
