# frozen_string_literal: true

module ChronoModel
  # Utility methods for converting time objects for use with temporal tables.
  module Conversions
    module_function

    # Converts a Time object to a UTC string with microsecond precision.
    #
    # @param time [Time] the time object to convert
    # @return [String] UTC time string with microsecond precision
    def time_to_utc_string(time)
      time.to_fs(:db) << '.' << format('%06d', time.usec)
    end
  end
end
