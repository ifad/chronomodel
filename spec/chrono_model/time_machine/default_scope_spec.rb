require 'spec_helper'
require 'support/time_machine/structure'

describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  # Set up database structure
  #
  adapter.create_table 'defoos', temporal: true do |t|
    t.string  :name
    t.boolean :active
  end

  class ::Defoo < ActiveRecord::Base
    include ChronoModel::TimeMachine

    default_scope proc { where(active: true) }
  end

  active = ts_eval { Defoo.create! name: 'active 1', active: true }
  ts_eval(active) { update! name: 'active 2' }

  hidden = ts_eval { Defoo.create! name: 'hidden 1', active: false }
  ts_eval(hidden) { update! name: 'hidden 2' }

  describe 'it honors default_scopes' do
    it { expect(Defoo.as_of(active.ts[0]).map(&:name)).to eq ['active 1'] }
    it { expect(Defoo.as_of(active.ts[1]).map(&:name)).to eq ['active 2'] }
    it { expect(Defoo.as_of(hidden.ts[0]).map(&:name)).to eq ['active 2'] }
    it { expect(Defoo.as_of(hidden.ts[1]).map(&:name)).to eq ['active 2'] }

    it { expect(Defoo.unscoped.as_of(active.ts[0]).map(&:name)).to eq ['active 1'] }
    it { expect(Defoo.unscoped.as_of(active.ts[1]).map(&:name)).to eq ['active 2'] }
    it { expect(Defoo.unscoped.as_of(hidden.ts[0]).map(&:name)).to eq ['active 2', 'hidden 1'] }
    it { expect(Defoo.unscoped.as_of(hidden.ts[1]).map(&:name)).to eq ['active 2', 'hidden 2'] }
  end
end
