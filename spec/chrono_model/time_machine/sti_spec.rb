# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

class Animal < ActiveRecord::Base
  include ChronoModel::TimeMachine
end

class Dog < Animal; end

class Goat < Animal; end

class Element < ActiveRecord::Base
  include ChronoModel::TimeMachine
end

class Publication < Element; end

class Magazine < Publication; end

# STI cases
#
# - https://github.com/ifad/chronomodel/issues/5
# - https://github.com/ifad/chronomodel/issues/47
#
RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  context 'with STI' do
    adapter.create_table 'elements', temporal: true do |t|
      t.string :title
      t.string :type
    end

    describe '.descendants' do
      subject { Element.descendants.map(&:name) }

      it { is_expected.to match_array %w[Publication Magazine] }
    end

    describe '.descendants_with_history' do
      subject { Element.descendants_with_history.map(&:name) }

      it { is_expected.to match_array %w[Element::History Publication Publication::History Magazine Magazine::History] }
    end

    if Element.respond_to?(:direct_descendants)
      describe '.direct_descendants' do
        subject { Element.direct_descendants.map(&:name) }

        it { is_expected.to match_array %w[Publication] }
      end

      describe '.direct_descendants_with_history' do
        subject { Element.direct_descendants_with_history.map(&:name) }

        it { is_expected.to match_array %w[Element::History Publication] }
      end
    end

    if Rails.version >= '7.0'
      describe '.subclasses' do
        subject { Element.subclasses.map(&:name) }

        it { is_expected.to match_array %w[Publication] }
      end

      describe '.subclasses_with_history' do
        subject { Element.subclasses_with_history.map(&:name) }

        it { is_expected.to match_array %w[Element::History Publication] }
      end
    end

    describe 'timeline' do
      let(:publication) do
        pub = ts_eval { Publication.create! title: 'wrong title' }
        ts_eval(pub) { update! title: 'correct title' }

        pub
      end

      it { expect(publication.history.map(&:title)).to eq ['wrong title', 'correct title'] }
    end

    describe 'identity' do
      let(:timestamp) { Time.now }

      adapter.create_table 'animals', temporal: true do |t|
        t.string :type
      end

      before do
        Dog.create!
        timestamp
        Goat.create!
      end

      after do
        tables = ['temporal.animals', 'history.animals']
        ActiveRecord::Base.connection.execute "truncate #{tables.join(', ')} cascade"
      end

      specify 'select' do
        expect(Animal.first).to be_a(Animal)
        expect(Animal.as_of(timestamp).first).to be_a(Animal)

        expect(Animal.where(type: 'Dog').first).to be_a(Dog)
        expect(Dog.first).to be_a(Dog)
        expect(Dog.as_of(timestamp).first).to be_a(Dog)

        expect(Animal.where(type: 'Goat').first).to be_a(Goat)
        expect(Goat.first).to be_a(Goat)
        expect(Goat.as_of(timestamp).first).to be_nil
        expect(Goat.as_of(Time.now).first).to be_a(Goat)
      end

      specify 'count' do
        expect(Animal.count).to eq(2)
        expect(Animal.as_of(timestamp).count).to eq(1)

        expect(Dog.count).to eq(1)
        expect(Dog.as_of(timestamp).count).to eq(1)

        expect(Goat.count).to eq(1)
        expect(Goat.as_of(timestamp).count).to eq(0)
      end
    end
  end
end
