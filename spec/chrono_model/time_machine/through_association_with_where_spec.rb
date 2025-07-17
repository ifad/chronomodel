# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

# This test reproduces the issue with has_many :through associations
# that include a where clause when used with as_of queries.
# See: https://github.com/ifad/chronomodel/issues/295
RSpec.describe 'Through associations with where clause' do
  include ChronoTest::TimeMachine::Helpers

  before(:all) do
    # Create a test model with a through association that has a where clause
    adapter.create_table 'councils', temporal: true do |t|
      t.string :name
      t.boolean :active, default: true
    end

    adapter.create_table 'memberships', temporal: true do |t|
      t.references :council
      t.references :person
      t.boolean :active, default: true
    end

    adapter.create_table 'people', temporal: true do |t|
      t.string :name
    end

    class Council < ActiveRecord::Base
      include ChronoModel::TimeMachine
      has_many :memberships
      has_many :people, through: :memberships
      has_many :active_people, -> { where(active: true) }, through: :memberships, source: :person
    end

    class Membership < ActiveRecord::Base
      include ChronoModel::TimeMachine
      belongs_to :council
      belongs_to :person
    end

    class Person < ActiveRecord::Base
      include ChronoModel::TimeMachine
      has_many :memberships
      has_many :councils, through: :memberships
      has_many :active_councils, -> { where(active: true) }, through: :memberships, source: :council
    end
  end

  after(:all) do
    Object.send(:remove_const, :Council)
    Object.send(:remove_const, :Membership)
    Object.send(:remove_const, :Person)
    
    adapter.drop_table :councils
    adapter.drop_table :memberships
    adapter.drop_table :people
  end

  let!(:council) { Council.create!(name: 'Test Council', active: true) }
  let!(:person) { Person.create!(name: 'Test Person') }
  let!(:membership) { Membership.create!(council: council, person: person, active: true) }
  
  let!(:timeline_point) { 1.hour.ago }

  before do
    # Travel back in time to create historical data
    Timecop.travel(timeline_point) do
      council.update!(name: 'Historical Council')
      person.update!(name: 'Historical Person')
    end
    Timecop.return
  end

  describe 'querying through associations with where clause using as_of' do
    context 'when the through association has a where clause' do
      it 'should not raise PG::UndefinedTable error' do
        expect {
          # This should work without error, but currently fails with:
          # PG::UndefinedTable: ERROR: relation "councils" does not exist
          Council.as_of(timeline_point).first.active_people.to_a
        }.not_to raise_error
      end

      it 'should correctly apply the where clause in the join context' do
        # Create inactive person to test the where clause
        inactive_person = Person.create!(name: 'Inactive Person')
        Membership.create!(council: council, person: inactive_person, active: false)

        # Get historical data
        historical_council = Council.as_of(timeline_point).first
        
        # Should only return active people
        active_people = historical_council.active_people.to_a
        expect(active_people.size).to eq(1)
        expect(active_people.first.name).to eq('Historical Person')
      end
    end

    context 'when querying from the other side of the association' do
      it 'should not raise PG::UndefinedTable error for person -> active_councils' do
        expect {
          Person.as_of(timeline_point).first.active_councils.to_a
        }.not_to raise_error
      end
    end
  end
end