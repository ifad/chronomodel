# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe 'concurrent updates' do
    it 'handles concurrent updates without PG::ExclusionViolation' do
      foo = Foo.create!(name: 'concurrency-test')

      threads_count = 4
      iterations = 10
      errors = []
      mutex = Mutex.new

      threads = Array.new(threads_count) do |i|
        Thread.new do
          iterations.times do |j|
            Foo.transaction do
              record = Foo.find(foo.id)
              record.update!(name: "iteration-#{i}-#{j}")
            end
          rescue StandardError => e
            mutex.synchronize do
              errors << "Thread #{i} Iteration #{j}: #{e.class} - #{e.message}"
            end
          end
        end
      end

      threads.each(&:join)

      expect(errors).to be_empty
    ensure
      # Clean up: delete the record and its history
      if foo
        foo.destroy
        Foo::History.where(id: foo.id).delete_all
      end
    end
  end

  describe 'concurrent deletions' do
    it 'handles concurrent deletions without error' do
      threads_count = 4
      foo_ids = Array.new(threads_count) { |i| Foo.create!(name: "test-delete-#{i}") }.map(&:id)
      errors = []
      mutex = Mutex.new

      threads = Array.new(threads_count) do |i|
        Thread.new do
          Foo.where(id: foo_ids[i]).delete_all
        rescue StandardError => e
          mutex.synchronize do
            errors << "Thread #{i}: #{e.class} - #{e.message}"
          end
        end
      end

      threads.each(&:join)

      expect(errors).to be_empty
      foo_ids.each do |id|
        expect(Foo.exists?(id)).to be(false)
      end
    ensure
      # Clean up any remaining records and history
      foo_ids&.each do |id|
        Foo::History.where(id: id).delete_all
        Foo.where(id: id).delete_all
      end
    end
  end
end
