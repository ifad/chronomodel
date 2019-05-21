require 'spec_helper'
require 'support/time_machine/structure'

describe Marcello do
  include ChronoTest::TimeMachine::Helpers

  describe '#table_name' do
    it "uses the specified table name" do
      expect(described_class.table_name).to eq('jekos')
    end

    it "uses the specified table name in history" do
      expect(described_class.history.table_name).to eq('history.jekos')
    end
  end

end
