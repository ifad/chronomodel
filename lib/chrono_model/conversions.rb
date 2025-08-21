# frozen_string_literal: true

module ChronoModel
  module Conversions
    module_function

    def time_to_utc_string(time)
      time.to_fs(:db) << '.' << format('%06d', time.usec)
    end

    # Returns the smallest time unit that ChronoModel can handle
    def timestamp_precision
      ChronoModel::TIMESTAMP_PRECISION
    end
  end
end
