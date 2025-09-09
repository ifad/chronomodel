# frozen_string_literal: true

module ChronoModel
  module TimeMachine
    # Provides functionality for history model classes that inherit from temporal models.
    #
    # This module is automatically included in dynamically created History classes
    # that inherit from temporal models. It provides access to historical data and
    # temporal query functionality.
    module HistoryModel
      extend ActiveSupport::Concern

      included do
        self.table_name = "#{Adapter::HISTORY_SCHEMA}.#{superclass.table_name}"

        scope :chronological, -> { order(Arel.sql('lower(validity) ASC')) }
      end

      # Finds a specific history record with optional locking.
      #
      # @param options [Hash] find options
      # @option options [Boolean, String, Symbol] :lock whether to lock the record
      # @return [ActiveRecord::Base] the found history record
      # @api private
      def _find_record(options)
        if options && options[:lock]
          self.class.preload(strict_loaded_associations).lock(options[:lock]).find_by!(hid: hid)
        else
          self.class.preload(strict_loaded_associations).find_by!(hid: hid)
        end
      end

      # Methods that make up the history interface of the companion History
      # model, automatically built for each Model that includes TimeMachine.
      module ClassMethods
        include ChronoModel::TimeMachine::TimeQuery
        include ChronoModel::TimeMachine::Timeline

        # Temporarily sets the primary key to 'hid' for history record operations.
        #
        # FIXME: find() and save() require the real history ID. So we are
        # setting it now and ensuring to reset it to the original one after
        # execution completes.
        #
        # @yield the block to execute with hid as primary key
        # @return [Object] the result of the yielded block
        def with_hid_pkey
          old = primary_key
          self.primary_key = 'hid'

          yield
        ensure
          self.primary_key = old
        end

        # Finds history records using the history ID as primary key.
        #
        # @param args [Array] arguments passed to find
        # @return [ActiveRecord::Base, Array<ActiveRecord::Base>] the found record(s)
        def find(*)
          with_hid_pkey { super }
        end

        # Executes a time query with validity interval pre-filled.
        #
        # In the History context, pre-fills the :on options with the validity interval.
        #
        # @param match [Symbol] the type of time query (:at, :before, :after, :contains, etc.)
        # @param time [Time, String] the time value for the query
        # @param options [Hash] query options
        # @option options [Symbol] :on the time column to query (defaults to :validity)
        # @return [ActiveRecord::Relation] the time-filtered relation
        def time_query(match, time, options = {})
          options[:on] ||= :validity
          super
        end

        # Returns past history records (those with closed validity ranges).
        #
        # @return [ActiveRecord::Relation] relation containing only past records
        def past
          time_query(:before, :now).where("NOT upper_inf(#{quoted_table_name}.validity)")
        end

        # Identifies this class as the History subclass.
        #
        # @return [Boolean] always returns true for history models
        def history?
          true
        end

        # Returns a relation with current timestamp as as_of_time.
        #
        # @return [ActiveRecord::Relation] relation with as_of_time set to now
        def relation
          super.as_of_time!(Time.now)
        end

        # Fetches records as of the specified time.
        #
        # @param time [Time] the timestamp to query records at
        # @return [ActiveRecord::Relation] relation scoped to the specified time
        def as_of(time)
          superclass.from(virtual_table_at(time)).as_of_time!(time)
        end

        # Creates a virtual table subquery for the specified time.
        #
        # @param time [Time] the timestamp for the virtual table
        # @param table_name [String, nil] optional table name to use in the subquery
        # @return [String] SQL fragment representing the virtual table
        def virtual_table_at(time, table_name: nil)
          virtual_name =
            if table_name
              connection.quote_table_name(table_name)
            else
              superclass.quoted_table_name
            end

          "(#{at(time).to_sql}) #{virtual_name}"
        end

        # Fetches history record at the given time.
        #
        # @param time [Time] the timestamp to fetch records at
        # @return [ActiveRecord::Relation] relation scoped to the specified time
        def at(time)
          time_query(:at, time).from(quoted_table_name).as_of_time!(time)
        end

        # Returns the history sorted by recorded_at timestamp.
        #
        # @return [ActiveRecord::Relation] history records sorted by recorded_at and hid
        def sorted
          all.order(Arel.sql(%(#{quoted_table_name}."recorded_at" ASC, #{quoted_table_name}."hid" ASC)))
        end

        # Fetches the history of the given object.
        #
        # Always includes an "as_of_time" column that is either the upper bound of the
        # validity range or now() if history validity is maximum.
        #
        # @param object [ActiveRecord::Base, Integer] the object or its ID to get history for
        # @return [ActiveRecord::Relation] relation containing the object's history
        def of(object)
          where(id: object)
        end

        # Returns the STI name for the history model.
        #
        # The `sti_name` method returns the contents of the inheritance column, and it
        # is usually the class name. The inherited class name has the "::History" suffix
        # but that is never going to be present in the data.
        #
        # As such it is overridden here to return the same contents that the parent would have returned.
        #
        # @return [String] the STI name from the superclass
        delegate :sti_name, to: :superclass

        # Returns whether this model descends from ActiveRecord::Base.
        #
        # For STI to work, the history model needs to have the exact same semantics as
        # the model it inherits from. However given it is actually inherited, the original
        # AR implementation would return false here. But for STI sake, the history model is
        # located in the same exact hierarchy location as its parent, thus this is defined
        # in this override.
        #
        # @return [Boolean] the result from the superclass
        delegate :descends_from_active_record?, to: :superclass

        private

        # Finds the STI class for history records.
        #
        # STI fails when a Foo::History record has Foo as type in the inheritance column;
        # AR expects the type to be an instance of the current class or a descendant (or self).
        #
        # @param type_name [String] the type name from the inheritance column
        # @return [Class] the STI class with ::History suffix added
        # @api private
        def find_sti_class(type_name)
          super("#{type_name}::History")
        end
      end

      # Returns the history ID for this record.
      #
      # The history id is `hid`, but this cannot set as primary key
      # or temporal associations will break. Solutions are welcome.
      #
      # @return [Integer] the history ID (hid)
      def id
        hid
      end

      # Returns the referenced record ID.
      #
      # @return [Integer] the ID of the original temporal record
      def rid
        attributes[self.class.primary_key]
      end

      # Saves the history record using the hid as primary key.
      #
      # @param args [Array] arguments passed to save
      # @return [Boolean] whether the save was successful
      def save(*)
        with_hid_pkey { super }
      end

      # Saves the history record using the hid as primary key, raising on failure.
      #
      # @param args [Array] arguments passed to save!
      # @return [Boolean] whether the save was successful
      # @raise [ActiveRecord::RecordInvalid] if validation fails
      def save!(*)
        with_hid_pkey { super }
      end

      # Updates columns directly using the hid as primary key.
      #
      # @param args [Array] arguments passed to update_columns
      # @return [Boolean] whether the update was successful
      def update_columns(*)
        with_hid_pkey { super }
      end

      # Indicates this record is historical.
      #
      # @return [Boolean] always returns true
      def historical?
        true
      end

      # Returns the previous history entry, or nil if this is the first one.
      #
      # @return [ActiveRecord::Base, nil] the previous history entry
      def pred
        return if valid_from.nil?

        if self.class.timeline_associations.empty?
          self.class.where('id = ? AND upper(validity) = ?', rid, valid_from).first
        else
          super(id: rid, before: valid_from, table: self.class.superclass.quoted_table_name)
        end
      end

      # Returns the next history entry, or nil if this is the last one.
      #
      # @return [ActiveRecord::Base, nil] the next history entry
      def succ
        return if valid_to.nil?

        if self.class.timeline_associations.empty?
          self.class.where('id = ? AND lower(validity) = ?', rid, valid_to).first
        else
          super(id: rid, after: valid_to, table: self.class.superclass.quoted_table_name)
        end
      end
      alias next succ

      # Returns the first history entry for this record.
      #
      # @return [ActiveRecord::Base] the first history entry
      def first
        self.class.where(id: rid).chronological.first
      end

      # Returns the last history entry for this record.
      #
      # @return [ActiveRecord::Base] the last history entry
      def last
        self.class.where(id: rid).chronological.last
      end

      # Returns this history entry's current record.
      #
      # @return [ActiveRecord::Base] the current version of this record
      def current_version
        self.class.superclass.find(rid)
      end

      # Returns the start time of this history entry's validity range.
      #
      # Return `nil` instead of -Infinity/Infinity to preserve current
      # Chronomodel behaviour and avoid failures with Rails 7.0 and
      # unbounded time ranges.
      #
      # Check if `begin` and `end` are `Time` because validity is a `tsrange`
      # column, so it is either `Time`, `nil`, and in some cases Infinity.
      #
      # Ref: rails/rails#45099
      # TODO: consider removing when Rails 7.0 support will be dropped
      #
      # @return [Time, nil] the start time of validity or nil if unbounded
      def valid_from
        validity.begin if validity.begin.is_a?(Time)
      end

      # Returns the end time of this history entry's validity range.
      #
      # @return [Time, nil] the end time of validity or nil if unbounded
      def valid_to
        validity.end if validity.end.is_a?(Time)
      end
      alias as_of_time valid_to

      # Reads an attribute value, handling primary key changes.
      #
      # `.read_attribute` uses the memoized `primary_key` if it detects
      # that the attribute name is `id`.
      #
      # Since the `primary key` may have been changed to `hid` because of
      # `.find` overload, the new behavior may break relations where `id` is
      # still the correct attribute to read.
      #
      # Ref: ifad/chronomodel#181
      #
      # @param attr_name [String, Symbol] the attribute name to read
      # @param block [Proc] optional block for attribute processing
      # @return [Object] the attribute value
      def read_attribute(attr_name, &block)
        return super unless attr_name.to_s == 'id' && @primary_key.to_s == 'hid'

        _read_attribute('id', &block)
      end

      private

      # Executes a block with hid as the primary key for this instance.
      #
      # @param block [Proc] the block to execute
      # @return [Object] the result of the block
      # @api private
      def with_hid_pkey(&block)
        old_primary_key = @primary_key
        @primary_key = 'hid'

        self.class.with_hid_pkey(&block)
      ensure
        @primary_key = old_primary_key
      end
    end
  end
end
