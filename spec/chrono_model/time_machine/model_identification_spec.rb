require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  adapter.create_table 'plains' do |t|
    t.string :foo
  end

  class ::Plain < ActiveRecord::Base
  end

  describe '.chrono?' do
    subject { model.chrono? }

    context 'on a temporal model' do
      let(:model) { Foo }

      it { is_expected.to be(true) }
    end

    context 'on a plain model' do
      let(:model) { Plain }

      it { is_expected.to be(false) }
    end
  end

  describe '.history?' do
    subject { model.history? }

    context 'on a temporal parent model' do
      let(:model) { Foo }

      it { is_expected.to be(false) }
    end

    context 'on a temporal history model' do
      let(:model) { Foo::History }

      it { is_expected.to be(true) }
    end

    context 'on a plain model' do
      let(:model) { Plain }

      it { expect { subject }.to raise_error(NoMethodError) }
    end
  end
end
