# frozen_string_literal: true

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'chrono_model'
require 'rails'

ActiveRecord::Base.establish_connection(adapter: 'chronomodel', database: 'chronomodel_bench')
ActiveRecord::Base.logger = nil
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  enable_extension :btree_gist

  drop_table :foos, if_exists: true

  create_table :foos, temporal: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :bars, force: true do |t|
    t.string :name
    t.timestamps
  end
end

class Foo < ActiveRecord::Base
  include ChronoModel::TimeMachine
end

class Bar < ActiveRecord::Base
  include ChronoModel::TimeGate
end

def run_benchmark_sample(iterations: 100)
  # Create
  iterations.times { |i| Foo.create! name: "Foo #{i}" }

  foo = Foo.create! name: 'Foo'

  # Update
  iterations.times { |i| foo.update! name: "New Foo #{i}" }

  # Destroy
  iterations.times { Foo.create!.destroy! }

  # Delete
  iterations.times { Foo.create!.delete }

  # Find
  iterations.times { |i| Foo.find(i + 1) }

  # Where
  iterations.times { |i| Foo.where(id: i + 1) }

  # as_of
  iterations.times { foo.as_of(1.day.ago) }

  # History
  iterations.times { foo.history.first }
  iterations.times { foo.history.last }

  iterations.times { Foo::History.sti_name }
end
