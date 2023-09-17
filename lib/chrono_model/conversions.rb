# frozen_string_literal: true

module ChronoModel
  module Conversions
    extend self

    ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(?:\.(\d+))?\z/.freeze

    # rubocop:disable Style/PerlBackrefs
    def string_to_utc_time(string)
      return string if string.is_a?(Time)

      return unless string =~ ISO_DATETIME

      # .1 is .100000, not .000001
      usec = $7.ljust(6, '0') unless $7.nil?

      Time.utc $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, usec.to_i
    end
    # rubocop:enable Style/PerlBackrefs

    def time_to_utc_string(time)
      time.to_formatted_s(:db) << '.' << format('%06d', time.usec)
    end
  end
end
