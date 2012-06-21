require 'spec_helper'
require 'support/helpers'

describe ChronoModel::TimeMachine do
  include ChronoTest::Helpers::TimeMachine

  setup_schema!
  define_models!

  describe '.chrono_models' do
    subject { ChronoModel::TimeMachine.chrono_models }

    it { should == {'foos' => Foo, 'bars' => Bar} }
  end

end
