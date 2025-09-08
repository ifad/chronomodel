# frozen_string_literal: true

module ChronoModel
  module Patches
    # Added to classes that need to carry the As-Of date around.
    module AsOfTimeHolder
      # Sets the virtual 'as_of_time' attribute to the given time, converting to UTC.
      #
      # @param time [Time, DateTime] the time to set, will be converted to UTC
      # @return [self] returns self for chaining
      def as_of_time!(time)
        @_as_of_time = time.utc

        self
      end

      # Reads the virtual 'as_of_time' attribute.
      #
      # @return [Time, nil] the current as_of_time or nil if not set
      def as_of_time
        @_as_of_time
      end
    end
  end
end
