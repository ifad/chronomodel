module ChronoModel

  module Conversions
    extend self

    ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(?:\.(\d+))?\z/

    def string_to_utc_time(string)
      if string =~ ISO_DATETIME
        usec = $7.nil? ? '000000' : $7.ljust(6, '0') # .1 is .100000, not .000001
        Time.utc $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, usec.to_i
      end
    end

    def time_to_utc_string(time)
      [time.to_s(:db), sprintf('%06d', time.usec)].join '.'
    end
  end

  module Json
    extend self

    def create
      adapter.execute 'CREATE OR REPLACE LANGUAGE plpythonu'
      adapter.execute File.read(sql 'json_ops.sql')
    end

    def drop
      adapter.execute File.read(sql 'uninstall-json_ops.sql')
      adapter.execute 'DROP LANGUAGE IF EXISTS plpythonu'
    end

    private
    def sql(file)
      File.dirname(__FILE__) + '/../../sql/' + file
    end

    def adapter
      ActiveRecord::Base.connection
    end
  end

  module Utilities
    # Amends the given history item setting a different period.
    # Useful when migrating from legacy systems.
    #
    def amend_period!(hid, from, to)
      unless [from, to].any? {|ts| ts.respond_to?(:zone) && ts.zone == 'UTC'}
        raise 'Can amend history only with UTC timestamps'
      end

      connection.execute %[
        UPDATE #{quoted_table_name}
           SET "validity" = tsrange(#{connection.quote(from)}, #{connection.quote(to)}),
               "recorded_at" = #{connection.quote(from)}
         WHERE "hid" = #{hid.to_i}
      ]
    end

    # Returns true if this model is backed by a temporal table,
    # false otherwise.
    #
    def chrono?
      connection.is_chrono?(table_name)
    end
  end

  ActiveRecord::Base.extend Utilities

end
