# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ChronoModel::Conversions do
  describe '.time_to_utc_string' do
    subject { described_class.time_to_utc_string(time) }

    let(:time) { Time.utc(1981, 4, 11, 2, 42, 10, 123_456) }

    it { is_expected.to eq '1981-04-11 02:42:10.123456' }
  end
end
