# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

class Plain < ActiveRecord::Base; end

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  adapter.create_table 'plains' do |t|
    t.string :foo
  end

  describe '.chrono?' do
    subject { model.chrono? }

    context 'with a temporal model' do
      let(:model) { Foo }

      it { is_expected.to be(true) }
    end

    context 'with a plain model' do
      let(:model) { Plain }

      it { is_expected.to be(false) }
    end
  end

  describe '.history?' do
    subject(:history?) { model.history? }

    context 'with a temporal parent model' do
      let(:model) { Foo }

      it { is_expected.to be(false) }
    end

    context 'with a temporal history model' do
      let(:model) { Foo::History }

      it { is_expected.to be(true) }
    end

    context 'with a plain model' do
      let(:model) { Plain }

      it { expect { history? }.to raise_error(NoMethodError) }
    end
  end
end
