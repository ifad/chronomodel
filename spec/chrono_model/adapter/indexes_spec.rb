# frozen_string_literal: true

require 'spec_helper'
require 'support/adapter/structure'

RSpec.describe ChronoModel::Adapter do
  include ChronoTest::Adapter::Structure

  before do
    adapter.create_table :meetings do |t|
      t.string :name
      t.tsrange :interval
    end
  end

  after do
    adapter.drop_table :meetings
  end

  describe '.add_temporal_indexes' do
    before do
      adapter.add_temporal_indexes :meetings, :interval
    end

    after do
      adapter.remove_temporal_indexes :meetings, :interval
    end

    it {
      expect(adapter.indexes(:meetings).map(&:name)).to eq %w[
        index_meetings_temporal_on_interval
        index_meetings_temporal_on_lower_interval
        index_meetings_temporal_on_upper_interval
      ]
    }
  end

  describe '.remove_temporal_indexes' do
    before do
      adapter.add_temporal_indexes :meetings, :interval
      adapter.remove_temporal_indexes :meetings, :interval
    end

    it { expect(adapter.indexes(:meetings)).to be_empty }
  end

  describe '.add_timeline_consistency_constraint' do
    before do
      adapter.add_timeline_consistency_constraint(:meetings, :interval)
    end

    after do
      adapter.remove_timeline_consistency_constraint(:meetings)
    end

    it {
      expect(adapter.indexes(:meetings).map(&:name)).to eq [
        'meetings_timeline_consistency'
      ]
    }
  end

  describe '.remove_timeline_consistency_constraint' do
    before do
      adapter.add_timeline_consistency_constraint :meetings, :interval
      adapter.remove_timeline_consistency_constraint(:meetings)
    end

    it { expect(adapter.indexes(:meetings)).to be_empty }
  end
end
