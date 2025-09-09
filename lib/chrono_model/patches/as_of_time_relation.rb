# frozen_string_literal: true

module ChronoModel
  module Patches
    # Dummy relation class for passing as_of_time parameters across ActiveRecord call chains.
    #
    # This class serves as a placeholder relation that carries temporal query parameters
    # through ActiveRecord's query building pipeline, specifically the as_of_time
    # timestamp used for temporal queries.
    class AsOfTimeRelation < ActiveRecord::Relation; end
  end
end
