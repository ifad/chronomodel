require 'spec_helper'
require 'support/helpers'

describe 'JSON equality operator' do
  include ChronoTest::Helpers::Adapter

  table 'json_test'

  before :all do
    ChronoModel::Json.create
  end

  after :all do
    ChronoModel::Json.drop
  end

  it { adapter.select_value(%[ SELECT '{"a":1}'::json = '{"a":1}'::json ]).should == 't' }
  it { adapter.select_value(%[ SELECT '{"a":1}'::json = '{"a" : 1}'::json ]).should == 't' }
  it { adapter.select_value(%[ SELECT '{"a":1}'::json = '{"a":2}'::json ]).should == 'f' }
  it { adapter.select_value(%[ SELECT '{"a":1,"b":2}'::json = '{"b":2,"a":1}'::json ]).should == 't' }
  it { adapter.select_value(%[ SELECT '{"a":1,"b":2,"x":{"c":4,"d":5}}'::json = '{"b":2, "x": { "d": 5, "c": 4}, "a":1}'::json ]).should == 't' }

  context 'on a temporal table' do
    before :all do
      adapter.create_table table, :temporal => true do |t|
        t.json 'data'
      end

      adapter.execute %[
        INSERT INTO #{table} ( data ) VALUES ( '{"a":1,"b":2}' )
      ]
    end

    after :all do
      adapter.drop_table table
    end

    it { expect {
      adapter.execute "UPDATE #{table} SET data = NULL"
    }.to_not raise_error }

    it { expect {
      adapter.execute %[UPDATE #{table} SET data = '{"x":1,"y":2}']

    }.to_not raise_error }
  end

end
