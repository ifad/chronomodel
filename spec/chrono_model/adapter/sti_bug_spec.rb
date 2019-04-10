require 'spec_helper'
require 'support/helpers'

describe 'models with STI' do
  include ChronoTest::Helpers::TimeMachine

  setup_schema!
  define_models!

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
