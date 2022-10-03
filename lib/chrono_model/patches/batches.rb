module ChronoModel
  module Patches
    module Batches
      module BatchEnumerator
        def each(&block)
          if @relation.try(:history?)
            @relation.with_hid_pkey { super }
          else
            super
          end
        end
      end
    end
  end
end
