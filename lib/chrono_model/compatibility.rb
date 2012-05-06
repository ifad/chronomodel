require 'active_record'

module ChronoModel

  # Utility methods added to every ActiveRecord::Base class instance
  # to check whether ChronoModel is supported and whether a model is
  # backed by temporal tables or not.
  #
  module Compatibility
    extend ActiveSupport::Concern

    # Returns true if this model is backed by a temporal table,
    # false otherwise.
    #
    def chrono?
      supports_chrono? && connection.is_chrono?(table_name)
    end

    # Returns true whether the connection adapter supports our
    # implementation of temporal tables. Currently, only the
    # PostgreSQL adapter is supported.
    #
    def supports_chrono?
      connection.respond_to?(:chrono_supported?) &&
        connection.chrono_supported?
    end
  end

end

ActiveRecord::Base.extend ChronoModel::Compatibility
