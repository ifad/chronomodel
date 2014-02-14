require 'active_record'

module ChronoModel

  # Utility methods added to every ActiveRecord::Base class instance
  # to check whether a model is backed by temporal tables or not.
  # FIXME move into Utilities
  module Compatibility
    # Returns true if this model is backed by a temporal table,
    # false otherwise.
    #
    def chrono?
      connection.is_chrono?(table_name)
    end
  end

end

ActiveRecord::Base.extend ChronoModel::Compatibility
