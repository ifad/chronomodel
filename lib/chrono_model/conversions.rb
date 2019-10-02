module ChronoModel

  module Conversions
    extend self

    ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(?:\.(\d+))?\z/

    def string_to_utc_time(string)
      return string if string.is_a?(Time)

      if string =~ ISO_DATETIME
        usec = $7.nil? ? '000000' : $7.ljust(6, '0') # .1 is .100000, not .000001
        Time.utc $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, usec.to_i
      end
    end

    def time_to_utc_string(time)
      [time.to_s(:db), sprintf('%06d', time.usec)].join '.'
    end
  end

end
