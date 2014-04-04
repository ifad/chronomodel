require 'spec_helper'
require 'support/helpers'

describe ChronoModel::TimeMachine::TimeQuery do
  include ChronoTest::Helpers::TimeMachine

  setup_schema!
  define_models!

  # Create a set of events
  #
  think   = Event.create! name: 'think',   interval: (15.days.ago.to_date...13.days.ago.to_date)
  plan    = Event.create! name: 'plan',    interval: (14.days.ago.to_date...12.days.ago.to_date)
  collect = Event.create! name: 'collect', interval: (12.days.ago.to_date...10.days.ago.to_date)
  start   = Event.create! name: 'start',   interval: (8.days.ago.to_date...7.days.ago.to_date)
  build   = Event.create! name: 'build',   interval: (7.days.ago.to_date...Date.yesterday)
  profit  = Event.create! name: 'profit',  interval: (Date.tomorrow...1.year.from_now.to_date)

  describe :at do
    describe 'with a single timestamp' do
      subject { Event.time_query(:at, time.try(:to_date) || time, on: :interval).to_a }

      context 'no records' do
        let(:time) { 16.days.ago }
        it { should be_empty }
      end

      context 'single record' do
        let(:time) { 15.days.ago }
        it { should == [think] }
      end

      context 'multiple overlapping records' do
        let(:time) { 14.days.ago }
        it { should =~ [think, plan] }
      end

      context 'on an edge of an open interval' do
        let(:time) { 10.days.ago }
        it { should be_empty }
      end

      context 'in an hole' do
        let(:time) { 9.days.ago }
        it { should be_empty }
      end

      context 'today' do
        let(:time) { Date.today }
        it { should be_empty }
      end

      context 'server-side :today' do
        let(:time) { :today }
        it { should be_empty }
      end
    end

    describe 'with a range' do
      subject { Event.time_query(:at, times.map!(&:to_date), on: :interval, type: :daterange).to_a }

      context 'that is empty' do
        let(:times) { [ 14.days.ago, 14.days.ago ] }
        it { should be_empty }
      end

      context 'overlapping no records' do
        let(:times) { [ 20.days.ago, 16.days.ago ] }
        it { should be_empty }
      end

      context 'overlapping a single record' do
        let(:times) { [ 16.days.ago, 14.days.ago ] }
        it { should == [think] }
      end

      context 'overlapping more records' do
        let(:times) { [ 16.days.ago, 11.days.ago ] }
        it { should =~ [think, plan, collect] }
      end

      context 'on the edge of an open interval and an hole' do
        let(:times) { [ 10.days.ago, 9.days.ago ] }
        it { should be_empty }
      end
    end
  end

  describe :before do
    let(:inclusive) { true }
    subject { Event.time_query(:before, time.try(:to_date) || time, on: :interval, type: :daterange, inclusive: inclusive).to_a }

    context '16 days ago' do
      let(:time) { 16.days.ago }
      it { should be_empty }
    end

    context '14 days ago' do
      let(:time) { 14.days.ago }
      it { should == [think] }

      context 'not inclusive' do
        let(:inclusive) { false }
        it { should be_empty }
      end
    end

    context '11 days ago' do
      let(:time) { 11.days.ago }
      it { should =~ [think, plan, collect] }

      context 'not inclusive' do
        let(:inclusive) { false }
        it { should == [think, plan] }
      end
    end

    context '10 days ago' do
      let(:time) { 10.days.ago }
      it { should =~ [think, plan, collect] }
    end

    context '8 days ago' do
      let(:time) { 8.days.ago }
      it { should =~ [think, plan, collect] }
    end

    context 'today' do
      let(:time) { Date.today }
      it { should =~ [think, plan, collect, start, build] }
    end

    context ':today' do
      let(:time) { :today }
      it { should =~ [think, plan, collect, start, build] }
    end
  end

  describe :after do
    let(:inclusive) { true }
    subject { Event.time_query(:after, time.try(:to_date) || time, on: :interval, type: :daterange, inclusive: inclusive).to_a }

    context 'one month ago' do
      let(:time) { 1.month.ago }
      it { should =~ [think, plan, collect, start, build, profit] }
    end

    context '10 days ago' do
      let(:time) { 10.days.ago }
      it { should =~ [start, build, profit] }
    end

    context 'yesterday' do
      let(:time) { Date.yesterday }
      it { should == [profit] }
    end

    context 'today' do
      let(:time) { Date.today }
      it { should == [profit] }
    end

    context 'server-side :today' do
      let(:time) { :today }
      it { should == [profit] }
    end

    context 'tomorrow' do
      let(:time) { Date.tomorrow }
      it { should == [profit] }
    end

    context 'one month from now' do
      let(:time) { 1.month.from_now }
      it { should == [profit] }

      context 'not inclusive' do
        let(:inclusive) { false }
        it { should be_empty }
      end
    end

    context 'far future' do
      let(:time) { 1.year.from_now }
      it { should be_empty }
    end
  end

  describe :not do
    context 'with a single timestamp' do
      subject { Event.time_query(:not, time.try(:to_date) || time, on: :interval, type: :daterange).to_a }

      context '14 days ago' do
        let(:time) { 14.days.ago }
        it { should =~ [collect, start, build, profit] }
      end

      context '9 days ago' do
        let(:time) { 9.days.ago }
        it { should =~ [think, plan, collect, start, build, profit] }
      end

      context '8 days ago' do
        let(:time) { 8.days.ago }
        it { should =~ [think, plan, collect, build, profit] }
      end

      context 'today' do
        let(:time) { Date.today }
        it { should =~ [think, plan, collect, start, build, profit] }
      end

      context ':today' do
        let(:time) { :today }
        it { should =~ [think, plan, collect, start, build, profit] }
      end

      context '1 month from now' do
        let(:time) { 1.month.from_now }
        it { should =~ [think, plan, collect, start, build] }
      end
    end

    context 'with a range' do
      subject { Event.time_query(:not, time.map(&:to_date), on: :interval, type: :daterange).to_a }

      context 'eliminating a single record' do
        let(:time) { [1.month.ago, 14.days.ago] }
        it { should =~ [plan, collect, start, build, profit] }
      end

      context 'eliminating multiple records' do
        let(:time) { [1.month.ago, Date.today] }
        it { should == [profit] }
      end

      context 'from an edge' do
        let(:time) { [14.days.ago, 10.days.ago] }
        it { should == [start, build, profit] }
      end
    end
  end

end
