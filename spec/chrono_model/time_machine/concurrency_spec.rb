# frozen_string_literal: true

require 'pg'

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  let(:pg_connection_config) do
    {
      dbname: ChronoTest.config[:database],
      user: ChronoTest.config[:username],
      host: ChronoTest.config[:host]
    }.tap do |config|
      password = ChronoTest.config[:password]
      config[:password] = password unless password.nil? || password.empty?
    end
  end

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

      if errors.any?
        puts "\nErrors encountered:"
        errors.each { |e| puts e }
      end

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
      connections = []

      begin
        stale = PG.connect(**pg_connection_config)
        t1 = PG.connect(**pg_connection_config)
        t2 = PG.connect(**pg_connection_config)
        connections.concat([stale, t1, t2])

        stale.exec('BEGIN')
        # Anchor the transaction timestamp before the later updates run.
        stale.exec("SELECT timezone('UTC', now())")

        sleep(0.05)
        t1.exec_params('UPDATE foos SET name = $1 WHERE id = $2', ['t1', foo.id])
        sleep(0.05)
        t2.exec_params('UPDATE foos SET name = $1 WHERE id = $2', ['t2', foo.id])
        sleep(0.05)

        stale.exec_params('UPDATE foos SET name = $1 WHERE id = $2', ['stale', foo.id])
        stale.exec('COMMIT')

        foo.reload

        expect(foo.name).to eq('stale')
        expect(Foo::History.where(id: foo.id).where('upper_inf(validity)').pick(:name)).to eq(foo.name)
      ensure
        if stale && stale.transaction_status != PG::PQTRANS_IDLE
          stale.exec('ROLLBACK')
        end
        connections.each { |connection| connection.close rescue nil }

        Foo.where(id: foo.id).delete_all if foo
        Foo::History.where(id: foo.id).delete_all if foo
      end
    end
  end

  describe 'concurrent deletions' do
    it 'handles concurrent deletions without error' do
      threads_count = 4
      foos = Array.new(threads_count) { |i| Foo.create!(name: "test-delete-#{i}") }
      foo_ids = foos.map(&:id)
      errors = []
      mutex = Mutex.new

      threads = Array.new(threads_count) do |i|
        Thread.new do
          Foo.transaction do
            foos[i].destroy
          end
        rescue StandardError => e
          mutex.synchronize do
            errors << "Thread #{i}: #{e.class} - #{e.message}"
          end
        end
      end

      threads.each(&:join)

      if errors.any?
        puts "\nErrors encountered:"
        errors.each { |e| puts e }
      end

      expect(errors).to be_empty
      foos.each do |foo|
        expect(Foo.exists?(foo.id)).to be(false)
      end
    ensure
      # Clean up any remaining records and history
      foo_ids&.each do |id|
        Foo.where(id: id).delete_all
        Foo::History.where(id: id).delete_all
      end
    end
  end
end
