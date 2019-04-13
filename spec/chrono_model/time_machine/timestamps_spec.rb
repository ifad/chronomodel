require 'spec_helper'
require 'support/helpers'
require 'spec/chrono_model/time_machine/schema'

describe ChronoModel::TimeMachine do
  include ChronoTest::Helpers::TimeMachine

  history_methods = %w( valid_from valid_to recorded_at )
  current_methods = %w( as_of_time )

  context 'on history records' do
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

  context 'on current records' do
    let(:record) { $t.foo }

    history_methods.each do |attr|
      describe ['#', attr].join do
        subject { record.public_send(attr) }

        it { expect { subject }.to raise_error(NoMethodError) }
      end
    end

    current_methods.each do |attr|
      describe ['#', attr].join do
        subject { record.public_send(attr) }

        it { is_expected.to be(nil) }
      end
    end
  end
end
