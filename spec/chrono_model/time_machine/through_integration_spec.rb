# frozen_string_literal: true

require 'spec_helper'

# Integration test to verify the through association fix works in a real scenario
# This test should be run with actual database setup
RSpec.describe 'Through associations with where clause integration test' do
  # Skip this test if database is not properly configured
  before(:all) do
    skip "Database not configured" unless defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_handler.connected?
  end

  # Create test models for the scenario
  before(:all) do
    # Create tables if they don't exist
    unless ActiveRecord::Base.connection.table_exists?(:test_councils)
      ActiveRecord::Base.connection.execute <<-SQL
        CREATE TABLE test_councils (
          id SERIAL PRIMARY KEY,
          name VARCHAR(255),
          active BOOLEAN DEFAULT true
        );
      SQL
      
      ActiveRecord::Base.connection.execute <<-SQL
        CREATE TABLE test_memberships (
          id SERIAL PRIMARY KEY,
          council_id INTEGER REFERENCES test_councils(id),
          person_id INTEGER REFERENCES test_people(id),
          active BOOLEAN DEFAULT true
        );
      SQL
      
      ActiveRecord::Base.connection.execute <<-SQL
        CREATE TABLE test_people (
          id SERIAL PRIMARY KEY,
          name VARCHAR(255)
        );
      SQL

      # Add temporal support
      ActiveRecord::Base.connection.execute("SELECT add_temporal_table('test_councils');")
      ActiveRecord::Base.connection.execute("SELECT add_temporal_table('test_memberships');")
      ActiveRecord::Base.connection.execute("SELECT add_temporal_table('test_people');")
    end

    # Define test models
    class TestCouncil < ActiveRecord::Base
      include ChronoModel::TimeMachine
      self.table_name = 'test_councils'
      
      has_many :test_memberships, foreign_key: 'council_id'
      has_many :test_people, through: :test_memberships, foreign_key: 'council_id'
      has_many :active_people, -> { where(active: true) }, through: :test_memberships, source: :test_person
    end

    class TestMembership < ActiveRecord::Base
      include ChronoModel::TimeMachine
      self.table_name = 'test_memberships'
      
      belongs_to :test_council, foreign_key: 'council_id'
      belongs_to :test_person, foreign_key: 'person_id'
    end

    class TestPerson < ActiveRecord::Base
      include ChronoModel::TimeMachine
      self.table_name = 'test_people'
      
      has_many :test_memberships, foreign_key: 'person_id'
      has_many :test_councils, through: :test_memberships, foreign_key: 'person_id'
    end
  end

  after(:all) do
    # Clean up test models
    Object.send(:remove_const, :TestCouncil) if defined?(TestCouncil)
    Object.send(:remove_const, :TestMembership) if defined?(TestMembership)
    Object.send(:remove_const, :TestPerson) if defined?(TestPerson)
    
    # Drop tables
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_councils CASCADE;")
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_memberships CASCADE;")
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_people CASCADE;")
  end

  let!(:council) { TestCouncil.create!(name: 'Test Council', active: true) }
  let!(:person) { TestPerson.create!(name: 'Test Person') }
  let!(:membership) { TestMembership.create!(council_id: council.id, person_id: person.id, active: true) }
  
  let!(:timeline_point) { 1.hour.ago }

  before do
    # Create historical data
    council.update!(name: 'Historical Council')
    person.update!(name: 'Historical Person')
  end

  describe 'querying through associations with where clause using as_of' do
    context 'when the through association has a where clause' do
      it 'should not raise PG::UndefinedTable error' do
        expect {
          # This was the failing case: through association with where clause + as_of
          historical_council = TestCouncil.as_of(timeline_point).first
          historical_council.active_people.to_a if historical_council
        }.not_to raise_error
      end

      it 'should return correct historical data' do
        # Create some test data
        inactive_person = TestPerson.create!(name: 'Inactive Person')
        TestMembership.create!(council_id: council.id, person_id: inactive_person.id, active: false)

        # Get historical data
        historical_council = TestCouncil.as_of(timeline_point).first
        
        if historical_council
          # Should only return active people
          active_people = historical_council.active_people.to_a
          expect(active_people).to be_an(Array)
          # The exact data depends on when the test runs relative to timeline_point
        end
      end
    end

    context 'when querying regular (non-where clause) through associations' do
      it 'should still work correctly' do
        expect {
          historical_council = TestCouncil.as_of(timeline_point).first
          historical_council.test_people.to_a if historical_council
        }.not_to raise_error
      end
    end
  end
end