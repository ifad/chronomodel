# frozen_string_literal: true

module ChronoModel
  module Conversions
    module_function

    def time_to_utc_string(time)
      time.to_fs(:db) << '.' << format('%06d', time.usec)
    end
  end
end
