# frozen_string_literal: true

module ChronoModel
  module Patches
    # Overrides the default batch methods for historical models.
    #
    # In the default implementation, `cursor` defaults to `primary_key`, which is 'id'.
    # However, historical models need to use 'hid' instead of 'id'.
    #
    # This patch addresses an issue where `with_hid_pkey` is called after the cursor.
    # is already set, potentially leading to incorrect behavior.
    #
    # Notes:
    # - `find_each` and `find_in_batches` internally utilize `in_batches`.
    #   However, in the upcoming Rails 8.0, this implementation will be
    #   insufficient due to a new conditional branch using `enum_for`.
    # - This approach prevents specifying 'id' as a cursor for historical models.
    #   If 'id' is needed, it must be handled separately.
    #
    # See: ifad/chronomodel#321 for more context.
    module Batches.
      def find_each(**options)
        return super unless try(:history?)

        options[:cursor] = 'hid' if options[:cursor] == 'id'

        with_hid_pkey { super }
      end

      def find_in_batches(**options)
        return super unless try(:history?)

        options[:cursor] = 'hid' if options[:cursor] == 'id'

        with_hid_pkey { super }
      end

      def in_batches(**options)
        return super unless try(:history?)

        options[:cursor] = 'hid' if options[:cursor] == 'id'

        with_hid_pkey { super }
      end
    end
  end
end
