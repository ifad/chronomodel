# frozen_string_literal: true

module ChronoModel
  # Provides the TimeMachine API to non-temporal models that associate
  # temporal ones.
  module TimeGate
    extend ActiveSupport::Concern

    include ChronoModel::Patches::AsOfTimeHolder

    module ClassMethods
      include ChronoModel::TimeMachine::Timeline

      # Returns a relation scoped to a specific time for all records.
      #
      # @param time [Time, DateTime] the time to scope to
      # @return [ActiveRecord::Relation] the scoped relation
      def as_of(time)
        all.as_of_time!(time)
      end
    end

    # Returns this record as it was at the specified time.
    #
    # @param time [Time, DateTime] the time to query for
    # @return [Object] the record as it was at that time
    # @raise [ActiveRecord::RecordNotFound] if no record is found at that time
    def as_of(time)
      self.class.as_of(time).where(id: id).first!
    end

    # Returns the timeline for this record.
    #
    # @return [Array<Time>] array of timestamps for the timeline
    def timeline
      self.class.timeline(self)
    end
  end
end
