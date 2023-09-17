# frozen_string_literal: true

module ChronoModel
  # Provides the TimeMachine API to non-temporal models that associate
  # temporal ones.
  #
  module TimeGate
    extend ActiveSupport::Concern

    include ChronoModel::Patches::AsOfTimeHolder

    module ClassMethods
      include ChronoModel::TimeMachine::Timeline

      def as_of(time)
        all.as_of_time!(time)
      end
    end

    def as_of(time)
      self.class.as_of(time).where(id: id).first!
    end

    def timeline
      self.class.timeline(self)
    end
  end
end
