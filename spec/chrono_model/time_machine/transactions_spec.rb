# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  # Transactions
  context 'with multiple updates to an existing record' do
    let!(:r1) do
      Foo.create!(name: 'xact test').tap do |record|
        Foo.transaction do
          record.update_column 'name', 'lost into oblivion'
          record.update_column 'name', 'does work'
        end
      end
    end

    after do
      r1.destroy
      r1.history.delete_all
    end

    it 'generates a single history record' do
      expect(r1.history.size).to eq(2)

      expect(r1.history.first.name).to eq 'xact test'
      expect(r1.history.last.name).to  eq 'does work'
    end
  end

  context 'with an insertion and subsequent update' do
    let!(:r2) do
      Foo.transaction do
        Foo.create!(name: 'lost into oblivion').tap do |record|
          record.update_column 'name', 'I am Bar'
          record.update_column 'name', 'I am Foo'
        end
      end
    end

    after do
      r2.destroy
      r2.history.delete_all
    end

    it 'generates a single history record' do
      expect(r2.history.size).to eq(1)
      expect(r2.history.first.name).to eq 'I am Foo'
    end
  end

  context 'with an insertion and subsequent deletion' do
    let!(:r3) do
      Foo.transaction do
        Foo.create!(name: 'it never happened').destroy
      end
    end

    after do
      r3.destroy
      r3.history.delete_all
    end

    it 'does not generate any history' do
      expect(Foo.history.where(id: r3.id)).to be_empty
    end
  end
end
