module ChronoModel

  # Provides the TimeMachine API to non-temporal models that associate
  # temporal ones.
  #
  module TimeGate
    extend ActiveSupport::Concern

    module ClassMethods
      def as_of(time)
        all.tap {|as_of| as_of.instance_variable_set(:@_as_of_time, time) }
      end

      include TimeMachine::HistoryMethods::Timeline
    end

    def as_of(time)
      self.class.as_of(time).where(:id => self.id).first!
    end

    def timeline
      self.class.timeline(self)
    end

    def as_of_time
      @_as_of_time
    end
  end

end
