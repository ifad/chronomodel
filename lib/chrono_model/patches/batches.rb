# frozen_string_literal: true

module ChronoModel
  module Patches
    # Overrides the default batch methods for historical models.
    #
    # In the default implementation, `cursor` defaults to `primary_key`, which is 'id'.
    # However, historical models need to use 'hid' instead of 'id'.
    #
    # This patch addresses an issue where `with_hid_pkey` is called after the cursor
    # is already set, potentially leading to incorrect behavior.
    #
    # Notes:
    # - `find_each` and `find_in_batches` internally utilize `in_batches`.
    #   However, in the upcoming Rails 8.0, this implementation will be
    #   insufficient due to a new conditional branch using `enum_for`.
    # - This approach prevents specifying 'id' as a cursor for historical models.
    #   If 'id' is needed, it must be handled separately.
    #
    # @see https://github.com/ifad/chronomodel/issues/321
    module Batches
      # Iterates over records in batches, modifying cursor for historical models.
      #
      # For historical models, automatically converts 'id' cursor to 'hid' and
      # ensures the correct primary key is used during iteration.
      #
      # @param options [Hash] batch iteration options
      # @option options [String, Symbol] :cursor the column to use for batching
      # @return [Enumerator] if no block given
      # @yield [ActiveRecord::Base] each record in the batch
      def find_each(**options)
        return super unless try(:history?)

        options[:cursor] = 'hid' if options[:cursor] == 'id'

        with_hid_pkey { super }
      end

      # Iterates over records in batches, yielding arrays of records.
      #
      # For historical models, automatically converts 'id' cursor to 'hid' and
      # ensures the correct primary key is used during iteration.
      #
      # @param options [Hash] batch iteration options
      # @option options [String, Symbol] :cursor the column to use for batching
      # @option options [Integer] :batch_size number of records per batch
      # @return [Enumerator] if no block given
      # @yield [Array<ActiveRecord::Base>] array of records in each batch
      def find_in_batches(**options)
        return super unless try(:history?)

        options[:cursor] = 'hid' if options[:cursor] == 'id'

        with_hid_pkey { super }
      end

      # Returns an ActiveRecord::Batches::BatchEnumerator for processing records in batches.
      #
      # For historical models, automatically converts 'id' cursor to 'hid' and
      # ensures the correct primary key is used during iteration.
      #
      # @param options [Hash] batch iteration options
      # @option options [String, Symbol] :cursor the column to use for batching
      # @option options [Integer] :batch_size number of records per batch
      # @return [ActiveRecord::Batches::BatchEnumerator] batch enumerator
      def in_batches(**options)
        return super unless try(:history?)

        options[:cursor] = 'hid' if options[:cursor] == 'id'

        with_hid_pkey { super }
      end
    end
  end
end
