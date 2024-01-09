# frozen_string_literal: true

module ChronoModel
  module Patches
    # This class is a dummy relation whose scope is only to pass around the
    # as_of_time parameters across ActiveRecord call chains.
    class AsOfTimeRelation < ActiveRecord::Relation; end
  end
end
