# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  history_methods = %w[valid_from valid_to recorded_at]
  current_methods = %w[as_of_time]

  context 'with history records' do
    let(:record) { $t.foo.history.first }

    (history_methods + current_methods).each do |attr|
      describe ['#', attr].join do
        subject { record.public_send(attr) }

        it { is_expected.to be_present }
        it { is_expected.to be_a(Time) }
        it { is_expected.to be_utc }
      end
    end
  end

  context 'with current records' do
    let(:record) { $t.foo }

    history_methods.each do |attr|
      describe ['#', attr].join do
        subject(:attribute) { record.public_send(attr) }

        it { expect { attribute }.to raise_error(NoMethodError) }
      end
    end

    current_methods.each do |attr|
      describe ['#', attr].join do
        subject { record.public_send(attr) }

        it { is_expected.to be_nil }
      end
    end
  end
end
