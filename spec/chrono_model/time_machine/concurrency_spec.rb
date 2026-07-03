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
          Foo.connection_pool.with_connection do
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

    it 'keeps the open history row aligned with the current row when an older transaction commits last' do
      foo = Foo.create!(name: 'orig')
      errors = []
      mutex = Mutex.new
      started = Queue.new
      proceed = Queue.new
      stale = nil
      stale_started = false

      begin
        stale = Thread.new do
          Foo.connection_pool.with_connection do
            Foo.transaction do
              Foo.connection.execute("SELECT timezone('UTC', now())")
              stale_started = true
              started << true
              proceed.pop
              Foo.find(foo.id).update!(name: 'stale')
            end
          end
        rescue StandardError => e
          started << true unless stale_started
          mutex.synchronize { errors << e }
        end

        started.pop
        sleep(0.05)
        Foo.find(foo.id).update!(name: 't1')
        sleep(0.05)
        Foo.find(foo.id).update!(name: 't2')

        proceed << true
        stale.join

        expect(errors).to be_empty
        expect(foo.reload.name).to eq('stale')
        expect(Foo::History.where(id: foo.id).where('upper_inf(validity)').pick(:name)).to eq(foo.name)
      ensure
        proceed << true if proceed && stale&.alive?
        stale&.join

        if foo
          Foo.where(id: foo.id).delete_all
          Foo::History.where(id: foo.id).delete_all
        end
      end
    end

    it 'suppresses a stale update when the current row is deleted while waiting for the lock' do
      foo = Foo.create!(name: 'delete-race')
      errors = []
      mutex = Mutex.new
      deleted = Queue.new
      commit = Queue.new
      updater_pid = Queue.new
      updated = nil
      deleter = nil
      updater = nil

      begin
        deleter = Thread.new do
          Foo.connection_pool.with_connection do
            Foo.transaction do
              Foo.where(id: foo.id).delete_all
              deleted << true
              commit.pop
            end
          end
        rescue StandardError => e
          deleted << true
          mutex.synchronize { errors << e }
        end

        deleted.pop

        updater = Thread.new do
          Foo.connection_pool.with_connection do |connection|
            updater_pid << connection.select_value('SELECT pg_backend_pid()')
            updated = connection.update("UPDATE foos SET name = 'stale' WHERE id = #{Integer(foo.id)}")
          end
        rescue StandardError => e
          updater_pid << nil
          mutex.synchronize { errors << e }
        end

        pid = updater_pid.pop
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        loop do
          wait_event = Foo.connection.select_value(<<~SQL.squish)
            SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}
          SQL
          break if wait_event == 'Lock'

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            raise 'stale update did not wait for the current-row lock'
          end

          sleep 0.01
        end

        commit << true
        deleter.join
        updater.join

        expect(errors).to be_empty
        expect(updated).to eq(0)
        expect(Foo.exists?(foo.id)).to be(false)
        expect(Foo::History.where(id: foo.id).where('upper_inf(validity)').count).to eq(0)
      ensure
        commit << true if deleter&.alive?
        deleter&.join
        updater&.join

        Foo.where(id: foo.id).delete_all if foo
        Foo::History.where(id: foo.id).delete_all if foo
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
          Foo.connection_pool.with_connection do
            Foo.where(id: foo_ids[i]).delete_all
          end
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
