module ChronoModel
  module Patches

    # Added to classes that need to carry the As-Of date around
    #
    module AsOfTimeHolder
      # Sets the virtual 'as_of_time' attribute to the given time, converting to UTC.
      #
      def as_of_time!(time)
        @_as_of_time = time.utc

        self
      end

      # Reads the virtual 'as_of_time' attribute
      #
      def as_of_time
        @_as_of_time
      end
    end

  end
end
