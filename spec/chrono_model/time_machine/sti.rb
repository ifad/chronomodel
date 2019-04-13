require 'spec_helper'
require 'support/helpers'

# STI cases
#
# - https://github.com/ifad/chronomodel/issues/5
# - https://github.com/ifad/chronomodel/issues/47
#
describe 'models with STI' do
  include ChronoTest::Helpers::TimeMachine

  adapter.create_table 'elements', :temporal => true do |t|
    t.string :title
    t.string :type
  end

  class ::Element < ActiveRecord::Base
    include ChronoModel::TimeMachine
  end

  class ::Publication < Element
  end

  describe '.descendants' do
    subject { Element.descendants }

    it { is_expected.to_not include(Element::History) }
    it { is_expected.to     include(Publication) }
  end

  describe '.descendants_with_history' do
    subject { Element.descendants_with_history }

    it { is_expected.to include(Element::History) }
    it { is_expected.to include(Publication) }
  end

  describe 'history timeline' do
    pub = ts_eval { Publication.create! :title => 'wrong title' }
    ts_eval(pub) { update_attributes! :title => 'correct title' }

    it { expect(pub.history.map(&:title)).to eq ['wrong title', 'correct title'] }
  end

  describe 'associations' do
    adapter.create_table 'animals', temporal: true do |t|
      t.string :type
    end

    class ::Animal < ActiveRecord::Base
      include ChronoModel::TimeMachine
    end

    class ::Dog < Animal
    end

    class ::Goat < Animal
    end

    before do
      Dog.create!
      @later = Time.new
      Goat.create!
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
      expect(Animal.count).to eq(2)
      expect(Animal.as_of(@later).count).to eq(1)

      expect(Dog.count).to eq(1)
      expect(Dog.as_of(@later).count).to eq(1)

      expect(Goat.count).to eq(1)
      expect(Goat.as_of(@later).count).to eq(0)
    end
  end
end
