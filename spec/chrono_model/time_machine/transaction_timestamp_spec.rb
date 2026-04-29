# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  after do
    Overlapper::History.delete_all
    Overlapper.delete_all
    OverlapBro::History.delete_all
    OverlapBro.delete_all
  end

  describe 'records created in the same transaction' do
    it 'are all visible in as_of() queries using the first record creation time' do
      first_record = nil
      second_record = nil
      third_record = nil

      Overlapper.transaction do
        first_record = Overlapper.create!(name: 'first')
        second_record = Overlapper.create!(name: 'second')
        third_record = Overlapper.create!(name: 'third')
      end

      Overlapper.transaction do
        Overlapper.create!(name: 'second transaction record')
      end

      # Get the validity start time of the first record from history
      first_record_validity_start = first_record.history.last.validity.begin

      # All records created in the same transaction should be visible
      # when querying as_of() with the first record's creation timestamp
      records_at_first_timestamp = Overlapper.as_of(first_record_validity_start)
      expect(records_at_first_timestamp.map(&:id)).to contain_exactly(first_record.id, second_record.id, third_record.id)
    end

    it 'allows querying associated records created in the same transaction' do
      overlap = nil

      Overlapper.transaction do
        bro = OverlapBro.create!(name: 'bro record')
        overlap = Overlapper.create!(name: 'child', overlap_bro: bro)
      end

      overlap_validity_start = overlap.history.last.validity.begin
      overlap_at_creation = Overlapper.as_of(overlap_validity_start).find(overlap.id)
      # Child record should be visible through the association
      expect(overlap_at_creation.overlap_bro.name).to eq('bro record')
    end

    it 'maintains consistent timestamps for records created together' do
      records = nil

      Overlapper.transaction do
        records = Array.new(5) { |i| Overlapper.create!(name: "record-#{i}") }
      end

      # All records should have the same validity start time (transaction time)
      validity_starts = records.map { |r| r.history.last.validity.begin }

      expect(validity_starts.uniq.size).to eq(1),
                                           "Expected all records to have the same validity start time, but got: #{validity_starts.inspect}"
    end
  end

  describe 'records updated in the same transaction' do
    # This test reproduces the issue where clock_timestamp() in UPDATE triggers
    # causes records updated within the same transaction to have different timestamps,
    # making them invisible in as_of() queries.
    #
    # Scenario:
    # 1. Create an "overlap_bro" record
    # 2. Create associated "overlappers" that reference this version
    # 3. Update the overlappers within the same transaction
    # 4. Query as_of(overlap_bro.created_at) should show all overlappers
    it 'updated records are visible in as_of() queries using the transaction start time' do
      bro = nil

      OverlapBro.transaction do
        bro = OverlapBro.create!(name: 'bro_v1')
        3.times do |i|
          overlap = Overlapper.create!(name: "overlapper_#{i}", overlap_bro: bro)
          overlap.update!(name: "overlapper_#{i}_updated")
        end
      end

      bro_created_at = bro.history.last.validity.begin

      # Query all overlappers as of the bro's creation time
      # With clock_timestamp() in UPDATE trigger, updated overlappers would have
      # a later timestamp and would NOT be visible here
      overlappers_at_bro_time = Overlapper.as_of(bro_created_at).where(overlap_bro_id: bro.id)

      expect(overlappers_at_bro_time.count).to eq(3),
                                               "Expected 3 overlappers visible at bro creation time, got #{overlappers_at_bro_time.count}"

      expect(overlappers_at_bro_time.map(&:name)).to contain_exactly(
        'overlapper_0_updated',
        'overlapper_1_updated',
        'overlapper_2_updated'
      )
    end

    it 'multiple updates in same transaction maintain consistent timestamp' do
      overlap = nil

      Overlapper.transaction do
        overlap = Overlapper.create!(name: 'original')
        overlap.update!(name: 'update1')
        overlap.update!(name: 'update2')
        overlap.update!(name: 'final')
      end

      # All history entries created in this transaction should share the same timestamp
      # (due to squashing or consistent now() usage)
      history_entries = overlap.history.order(:hid)

      # The final state should be visible at the creation timestamp
      creation_time = history_entries.first.validity.begin
      overlap_at_creation = Overlapper.as_of(creation_time).find(overlap.id)
      expect(overlap_at_creation.name).to eq('final')
    end
  end

  describe 'records updated after initial creation' do
    it 'handles updates without timestamp conflicts' do
      overlap = Overlapper.create!(name: 'original')

      # Sleep a tiny bit to ensure different transaction time
      sleep(0.01)

      overlap.update!(name: 'updated')

      # The update should succeed and create a valid history entry
      overlap.reload
      expect(overlap.name).to eq('updated')

      # History should have entries with non-overlapping validity ranges
      history_entries = overlap.history.order(:hid)
      expect(history_entries.size).to eq 2
    end
  end
end
