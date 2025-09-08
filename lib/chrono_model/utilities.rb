# frozen_string_literal: true

module ChronoModel
  # Utility methods for working with ChronoModel history records.
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
    # @param hid [Integer] the history ID to amend
    # @param from [Time] the start time for the new period (must be UTC)
    # @param to [Time] the end time for the new period (must be UTC)
    # @return [void]
    # @raise [RuntimeError] if timestamps are not in UTC
    def amend_period!(hid, from, to)
      unless [from, to].any? { |ts| ts.respond_to?(:zone) && ts.zone == 'UTC' }
        raise 'Can amend history only with UTC timestamps'
      end

      connection.execute <<~SQL.squish
        UPDATE #{quoted_table_name}
           SET "validity"    = tsrange(#{connection.quote(from)}, #{connection.quote(to)}),
               "recorded_at" = #{connection.quote(from)}
         WHERE "hid" = #{hid.to_i}
      SQL
    end
  end
end
