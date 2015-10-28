module ChronoModel

  # Provides the TimeMachine API to non-temporal models that associate
  # temporal ones.
  #
  module TimeGate
    extend ActiveSupport::Concern

    module ClassMethods
      def as_of(time)
        all.as_of_time!(time)
      end

      include TimeMachine::HistoryMethods::Timeline
    end

    include Patches::AsOfTimeHolder

    def as_of(time)
      self.class.as_of(time).where(:id => self.id).first!
    end

    def timeline
      self.class.timeline(self)
    end
  end

end
