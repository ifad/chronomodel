# frozen_string_literal: true

module ChronoModel
  module Patches
    module Batches
      def in_batches(**)
        return super unless try(:history?)

        with_hid_pkey { super }
      end
    end
  end
end
