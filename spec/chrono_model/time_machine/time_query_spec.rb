# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

class Event < ActiveRecord::Base
  extend ChronoModel::TimeMachine::TimeQuery
end

RSpec.describe ChronoModel::TimeMachine::TimeQuery do
  include ChronoTest::TimeMachine::Helpers

  adapter.create_table 'events' do |t|
    t.string :name
    t.daterange :interval
  end

  # Main timeline quick test
  #
  it { expect(Foo.history.time_query(:after,  :now, inclusive: true).count).to eq 3 }
  it { expect(Foo.history.time_query(:after,  :now, inclusive: false).count).to eq 0 }
  it { expect(Foo.history.time_query(:before, :now, inclusive: true).count).to eq 5 }
  it { expect(Foo.history.time_query(:before, :now, inclusive: false).count).to eq 2 }

  it { expect(Foo.history.past.size).to eq 2 }

  # Extended thorough test.
  #
  # Create a set of events and then run time queries on them.
  #
  think   = Event.create! name: 'think',   interval: (15.days.ago.to_date...13.days.ago.to_date)
  plan    = Event.create! name: 'plan',    interval: (14.days.ago.to_date...12.days.ago.to_date)
  collect = Event.create! name: 'collect', interval: (12.days.ago.to_date...10.days.ago.to_date)
  start   = Event.create! name: 'start',   interval: (8.days.ago.to_date...7.days.ago.to_date)
  build   = Event.create! name: 'build',   interval: (7.days.ago.to_date...Date.yesterday)
  profit  = Event.create! name: 'profit',  interval: (Date.tomorrow...1.year.from_now.to_date)

  describe 'at' do
    context 'with a single timestamp' do
      subject { Event.time_query(:at, time.try(:to_date) || time, on: :interval).to_a }

      context 'without records' do
        let(:time) { 16.days.ago }

        it { is_expected.to be_empty }
      end

      context 'with a single record' do
        let(:time) { 15.days.ago }

        it { is_expected.to eq [think] }
      end

      context 'with multiple overlapping records' do
        let(:time) { 14.days.ago }

        it { is_expected.to contain_exactly(think, plan) }
      end

      context 'when on an edge of an open interval' do
        let(:time) { 10.days.ago }

        it { is_expected.to be_empty }
      end

      context 'with a hole' do
        let(:time) { 9.days.ago }

        it { is_expected.to be_empty }
      end

      context 'when today' do
        let(:time) { Date.today }

        it { is_expected.to be_empty }
      end

      context 'when server-side :today' do
        let(:time) { :today }

        it { is_expected.to be_empty }
      end
    end

    describe 'with a range' do
      subject { Event.time_query(:at, times.map!(&:to_date), on: :interval, type: :daterange).to_a }

      context 'with an empty range' do
        let(:times) { [14.days.ago, 14.days.ago] }

        it { is_expected.not_to be_empty }
      end

      context 'when range has no records' do
        let(:times) { [20.days.ago, 16.days.ago] }

        it { is_expected.to be_empty }
      end

      context 'when range has a single record' do
        let(:times) { [16.days.ago, 14.days.ago] }

        it { is_expected.to eq [think] }
      end

      context 'when range has multiple records' do
        let(:times) { [16.days.ago, 11.days.ago] }

        it { is_expected.to contain_exactly(think, plan, collect) }
      end

      context 'when on the edge of an open interval and a hole' do
        let(:times) { [10.days.ago, 9.days.ago] }

        it { is_expected.to be_empty }
      end
    end
  end

  describe 'before' do
    subject { Event.time_query(:before, time.try(:to_date) || time, on: :interval, type: :daterange, inclusive: inclusive).to_a }

    let(:inclusive) { true }

    context 'when 16 days ago' do
      let(:time) { 16.days.ago }

      it { is_expected.to be_empty }
    end

    context 'when 14 days ago' do
      let(:time) { 14.days.ago }

      it { is_expected.to eq [think] }

      context 'when not inclusive' do
        let(:inclusive) { false }

        it { is_expected.to be_empty }
      end
    end

    context 'when 11 days ago' do
      let(:time) { 11.days.ago }

      it { is_expected.to contain_exactly(think, plan, collect) }

      context 'when not inclusive' do
        let(:inclusive) { false }

        it { is_expected.to eq [think, plan] }
      end
    end

    context 'when 10 days ago' do
      let(:time) { 10.days.ago }

      it { is_expected.to contain_exactly(think, plan, collect) }
    end

    context 'when 8 days ago' do
      let(:time) { 8.days.ago }

      it { is_expected.to contain_exactly(think, plan, collect) }
    end

    context 'when today' do
      let(:time) { Date.today }

      it { is_expected.to contain_exactly(think, plan, collect, start, build) }
    end

    context 'when server-side :today' do
      let(:time) { :today }

      it { is_expected.to contain_exactly(think, plan, collect, start, build) }
    end
  end

  describe 'after' do
    subject { Event.time_query(:after, time.try(:to_date) || time, on: :interval, type: :daterange, inclusive: inclusive).to_a }

    let(:inclusive) { true }

    context 'when one month ago' do
      let(:time) { 1.month.ago }

      it { is_expected.to contain_exactly(think, plan, collect, start, build, profit) }
    end

    context 'when 10 days ago' do
      let(:time) { 10.days.ago }

      it { is_expected.to contain_exactly(start, build, profit) }
    end

    context 'when yesterday' do
      let(:time) { Date.yesterday }

      it { is_expected.to eq [profit] }
    end

    context 'when today' do
      let(:time) { Date.today }

      it { is_expected.to eq [profit] }
    end

    context 'when server-side :today' do
      let(:time) { :today }

      it { is_expected.to eq [profit] }
    end

    context 'when tomorrow' do
      let(:time) { Date.tomorrow }

      it { is_expected.to eq [profit] }
    end

    context 'when one month from now' do
      let(:time) { 1.month.from_now }

      it { is_expected.to eq [profit] }

      context 'when not inclusive' do
        let(:inclusive) { false }

        it { is_expected.to be_empty }
      end
    end

    context 'when far future' do
      let(:time) { 1.year.from_now }

      it { is_expected.to be_empty }
    end
  end

  describe 'not' do
    context 'with a single timestamp' do
      subject { Event.time_query(:not, time.try(:to_date) || time, on: :interval, type: :daterange).to_a }

      context 'when 14 days ago' do
        let(:time) { 14.days.ago }

        it { is_expected.to contain_exactly(collect, start, build, profit) }
      end

      context 'when 9 days ago' do
        let(:time) { 9.days.ago }

        it { is_expected.to contain_exactly(think, plan, collect, start, build, profit) }
      end

      context 'when 8 days ago' do
        let(:time) { 8.days.ago }

        it { is_expected.to contain_exactly(think, plan, collect, build, profit) }
      end

      context 'when today' do
        let(:time) { Date.today }

        it { is_expected.to contain_exactly(think, plan, collect, start, build, profit) }
      end

      context 'when server-side :today' do
        let(:time) { :today }

        it { is_expected.to contain_exactly(think, plan, collect, start, build, profit) }
      end

      context 'when 1 month from now' do
        let(:time) { 1.month.from_now }

        it { is_expected.to contain_exactly(think, plan, collect, start, build) }
      end
    end

    context 'with a range' do
      subject { Event.time_query(:not, time.map(&:to_date), on: :interval, type: :daterange).to_a }

      context 'when eliminating a single record' do
        let(:time) { [1.month.ago, 14.days.ago] }

        it { is_expected.to contain_exactly(plan, collect, start, build, profit) }
      end

      context 'when eliminating multiple records' do
        let(:time) { [1.month.ago, Date.today] }

        it { is_expected.to eq [profit] }
      end

      context 'with an edge' do
        let(:time) { [14.days.ago, 10.days.ago] }

        it { is_expected.to eq [start, build, profit] }
      end
    end
  end
end
