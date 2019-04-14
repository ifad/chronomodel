require 'support/time_machine/helpers'

# This module contains the test DDL and models used by most of the
# +TimeMachine+ specs.
#
# The models exercise different ActiveRecord features.
#
# They look candidate of unwinding by their respective specs, however this
# test suite aims also at testing within a "real" use case scenario, in which
# multiple models are defined and they interact - with their AR side effects,
# still ChronoModel should provide the expected results.
#
# The +$t+ global variable holds a timeline of events that have happened in
# the form of .create! and update_attributes, that aim to mimic the most of
# AR with the least of the effort. Full coverage exercises are most welcome.
#
module ChronoTest::TimeMachine
  include ChronoTest::TimeMachine::Helpers

  # Set up database structure
  #
  adapter.create_table 'foos', :temporal => true do |t|
    t.string     :name
    t.integer    :fooity
  end

  class ::Foo < ActiveRecord::Base
    include ChronoModel::TimeMachine

    has_many :bars
    has_many :sub_bars, :through => :bars
  end


  adapter.create_table 'bars', :temporal => true do |t|
    t.string     :name
    t.references :foo
  end

  class ::Bar < ActiveRecord::Base
    include ChronoModel::TimeMachine

    belongs_to :foo
    has_many :sub_bars
    has_one :baz

    has_timeline :with => :foo
  end


  adapter.create_table 'sub_bars', :temporal => true do |t|
    t.string     :name
    t.references :bar
  end

  class ::SubBar < ActiveRecord::Base
    include ChronoModel::TimeMachine

    belongs_to :bar

    has_timeline :with => :bar
  end


  adapter.create_table 'bazs' do |t|
    t.string     :name
    t.references :bar
  end

  class ::Baz < ActiveRecord::Base
    include ChronoModel::TimeGate

    belongs_to :bar

    has_timeline :with => :bar
  end

  # Master timeline, used in multiple specs. It is defined here
  # as a global variable to be able to be shared across specs.
  #
  $t = Struct.new(:foo, :bar, :baz, :subbar, :foos, :bars).new

  # Set up associated records, with intertwined updates
  #
  $t.foo = ts_eval { Foo.create! :name => 'foo', :fooity => 1 }
  ts_eval($t.foo) { update_attributes! :name => 'foo bar' }

  #
  $t.bar = ts_eval { Bar.create! :name => 'bar', :foo => $t.foo }
  ts_eval($t.bar) { update_attributes! :name => 'foo bar' }

  #
  $t.subbar = ts_eval { SubBar.create! :name => 'sub-bar', :bar => $t.bar }
  ts_eval($t.subbar) { update_attributes! :name => 'bar sub-bar' }

  ts_eval($t.foo) { update_attributes! :name => 'new foo' }

  ts_eval($t.bar) { update_attributes! :name => 'bar bar' }
  ts_eval($t.bar) { update_attributes! :name => 'new bar' }

  ts_eval($t.subbar) { update_attributes! :name => 'sub-bar sub-bar' }
  ts_eval($t.subbar) { update_attributes! :name => 'new sub-bar' }

  #
  $t.foos = Array.new(2) {|i| ts_eval { Foo.create! :name => "foo #{i}" } }
  $t.bars = Array.new(2) {|i| ts_eval { Bar.create! :name => "bar #{i}", :foo => $t.foos[i] } }

  #
  $t.baz = Baz.create :name => 'baz', :bar => $t.bar

end
