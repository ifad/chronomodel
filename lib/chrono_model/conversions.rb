# frozen_string_literal: true

module ChronoModel
  module Conversions
    module_function

    ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(?:\.(\d+))?\z/

    def time_to_utc_string(time)
      time.to_fs(:db) << '.' << format('%06d', time.usec)
    end
  end
end
