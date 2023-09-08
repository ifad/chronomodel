require 'spec_helper'

RSpec.describe ChronoModel::Conversions do
  describe 'string_to_utc_time' do
    subject { described_class.string_to_utc_time(string) }

    context 'given a valid UTC time string' do
      let(:string) { '2017-02-06 09:46:31.129626' }

      it { is_expected.to be_a(Time) }
      it { expect(subject.year).to  eq 2017 }
      it { expect(subject.month).to eq 2 }
      it { expect(subject.day).to   eq 6 }
      it { expect(subject.hour).to  eq 9 }
      it { expect(subject.min).to   eq 46 }
      it { expect(subject.sec).to   eq 31 }
      it { expect(subject.usec).to  eq 129_626 } # Ref Issue #32
    end

    context 'given a valid UTC string without least significant zeros' do
      let(:string) { '2017-02-06 09:46:31.129' }

      it { is_expected.to be_a(Time) }
      it { expect(subject.usec).to eq 129_000 } # Ref Issue #32
    end

    context 'given an invalid UTC time string' do
      let(:string) { 'foobar' }

      it { is_expected.to be_nil }
    end
  end

  describe 'time_to_utc_string' do
    subject { described_class.time_to_utc_string(time) }

    let(:time) { Time.utc(1981, 4, 11, 2, 42, 10, 123_456) }

    it { is_expected.to eq '1981-04-11 02:42:10.123456' }
  end
end
