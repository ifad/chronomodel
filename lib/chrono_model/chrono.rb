# frozen_string_literal: true

module ChronoModel
  # A module to add to ActiveRecord::Base to check if they are backed by
  # temporal tables.
  module Chrono
    # Checks whether this Active Record model is backed by a temporal table
    #
    # @return [Boolean] false if the connection does not respond to is_chrono?
    #   the result of connection.is_chrono?(table_name) otherwise
    def chrono?
      return false unless connection.respond_to? :is_chrono?

      connection.is_chrono?(table_name)
    end
  end
end
