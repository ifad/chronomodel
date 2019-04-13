require 'spec_helper'
require 'support/helpers'

describe 'models with STI' do
  include ChronoTest::Helpers::TimeMachine

  adapter.create_table 'animals', temporal: true do |t|
    t.string :type
  end

  class ::Animal < ActiveRecord::Base
    include ChronoModel::TimeMachine
  end

  class ::Dog < Animal
  end

  describe 'it generates the right queries' do
    before do
      Dog.create!
      @later = Time.new
    end

    after do
      tables = ['temporal.animals', 'history.animals']
      ActiveRecord::Base.connection.execute "truncate #{tables.join(', ')} cascade"
    end

    specify "select" do
      expect(Animal.first).to_not be_nil
      expect(Animal.as_of(@later).first).to_not be_nil
    end

    specify "count" do
      expect(Animal.count).to eq(1)
      expect(Animal.as_of(@later).count).to eq(1)
    end
  end
end
