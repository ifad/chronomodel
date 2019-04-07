module ChronoModel

  module Utilities
    # Amends the given history item setting a different period.
    # Useful when migrating from legacy systems.
    #
    # To use it, extend AR::Base with ChronoModel::Utilities
    #
    #   ActiveRecord::Base.instance_eval do
    #     extend ChronoModel::Utilities
    #   end
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
  end

end
