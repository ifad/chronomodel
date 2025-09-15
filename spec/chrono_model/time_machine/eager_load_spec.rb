# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe 'eager_load + as_of', :db do
  include ChronoTest::TimeMachine::Helpers

  it 'applies as_of_time to eager_load(:foo) on Bar (belongs_to)' do
    t = $t.bar.ts[1]
    bar = Bar.as_of(t).eager_load(:foo).first
    expect(bar.foo.name).to eq('foo bar')
  end

  it 'applies as_of_time to eager_load(:bars) on Foo (has_many)' do
    t = $t.foo.ts[2]
    foo = Foo.as_of(t).eager_load(:bars).first
    expect(foo.bars.first.name).to eq('foo bar')
  end

  it 'keeps as_of_time for subsequent traversals from eager-loaded records' do
    t = $t.bar.ts[1]
    bar = Bar.as_of(t).eager_load(:foo).first
    expect(bar.foo.name).to eq('foo bar')
    expect(bar.foo.bars).to be_a(Array)
  end

  it 'rewrites joined tables to history subqueries during eager_load' do
    t = $t.bar.ts[1]
    sql = Bar.as_of(t).eager_load(:foo).to_sql
    expect(sql).to match(/FROM\s*\(\s*SELECT\s+"history"\."foos"\..*validity/i)
  end
end