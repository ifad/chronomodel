# frozen_string_literal: true

module ChronoModel
  module Conversions
    module_function

    # ChronoModel uses microsecond precision for timestamps
    TIMESTAMP_PRECISION = Rational(1, 1_000_000) # 1 microsecond

    def time_to_utc_string(time)
      time.to_fs(:db) << '.' << format('%06d', time.usec)
    end

    # Returns the smallest time unit that ChronoModel can handle
    def timestamp_precision
      TIMESTAMP_PRECISION
    end
  end
end
