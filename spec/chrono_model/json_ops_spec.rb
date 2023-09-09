##########################################################
### DEPRECATED: JSON operators are an hack and there is no
### reason not to use jsonb other than migrating your data
##########################################################
if ENV['HAVE_PLPYTHON'] == '1'

  require 'spec_helper'
  require 'support/adapter/helpers'

  require 'chrono_model/json'

  RSpec.describe 'JSON equality operator' do
    include ChronoTest::Adapter::Helpers

    table 'json_test'

    before :all do
      ChronoModel::Json.create
    end

    after :all do
      ChronoModel::Json.drop
    end

    it { expect(adapter.select_value(%( SELECT '{"a":1}'::json = '{"a":1}'::json ))).to be true }
    it { expect(adapter.select_value(%( SELECT '{"a":1}'::json = '{"a" : 1}'::json ))).to be true }
    it { expect(adapter.select_value(%( SELECT '{"a":1}'::json = '{"a":2}'::json ))).to be false }
    it { expect(adapter.select_value(%( SELECT '{"a":1,"b":2}'::json = '{"b":2,"a":1}'::json ))).to be true }

    it {
      expect(adapter.select_value(%( SELECT '{"a":1,"b":2,"x":{"c":4,"d":5}}'::json = '{"b":2, "x": { "d": 5, "c": 4}, "a":1}'::json ))).to be true
    }

    context 'with a temporal table' do
      before :all do
        adapter.create_table table, temporal: true do |t|
          t.json 'data'
        end

        adapter.execute %[
        INSERT INTO #{table} ( data ) VALUES ( '{"a":1,"b":2}' )
      ]
      end

      after :all do
        adapter.drop_table table
      end

      it {
        expect do
          adapter.execute "UPDATE #{table} SET data = NULL"
        end.not_to raise_error
      }

      it {
        expect do
          adapter.execute %(UPDATE #{table} SET data = '{"x":1,"y":2}')
        end.not_to raise_error
      }
    end
  end

end
