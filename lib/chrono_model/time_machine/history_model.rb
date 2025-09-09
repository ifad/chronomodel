# frozen_string_literal: true

module ChronoModel
  module TimeMachine
    module HistoryModel
      extend ActiveSupport::Concern

      included do
        self.table_name = "#{Adapter::HISTORY_SCHEMA}.#{superclass.table_name}"

        scope :chronological, -> { order(Arel.sql('lower(validity) ASC')) }
      end

      def _find_record(options)
        if options && options[:lock]
          self.class.preload(strict_loaded_associations).lock(options[:lock]).find_by!(hid: hid)
        else
          self.class.preload(strict_loaded_associations).find_by!(hid: hid)
        end
      end

      # Methods that make up the history interface of the companion History
      # model, automatically built for each Model that includes TimeMachine
      #
      module ClassMethods
        include ChronoModel::TimeMachine::TimeQuery
        include ChronoModel::TimeMachine::Timeline

        # HACK. find() and save() require the real history ID. So we are
        # setting it now and ensuring to reset it to the original one after
        # execution completes. FIXME
        #
        def with_hid_pkey
          old = primary_key
          self.primary_key = 'hid'

          yield
        ensure
          self.primary_key = old
        end

        def find(*)
          with_hid_pkey { super }
        end

        # In the History context, pre-fill the :on options with the validity interval.
        #
        def time_query(match, time, options = {})
          options[:on] ||= :validity
          super
        end

        def past
          time_query(:before, :now).where("NOT upper_inf(#{quoted_table_name}.validity)")
        end

        # To identify this class as the History subclass
        def history?
          true
        end

        def relation
          super.as_of_time!(Time.now)
        end

        # Fetches as of +time+ records.
        #
        def as_of(time)
          superclass.from(virtual_table_at(time)).as_of_time!(time)
        end

        def virtual_table_at(time, table_name: nil)
          virtual_name =
            if table_name
              connection.quote_table_name(table_name)
            else
              superclass.quoted_table_name
            end

          "(#{at(time).to_sql}) #{virtual_name}"
        end

        # Fetches history record at the given time
        #
        # Build on an unscoped relation to avoid leaking outer predicates
        # (e.g., through association scopes) into the inner subquery.
        #
        # @see https://github.com/ifad/chronomodel/issues/295
        def at(time)
          unscoped.time_query(:at, time).from(quoted_table_name).as_of_time!(time)
        end

        # Returns the history sorted by recorded_at
        #
        def sorted
          all.order(Arel.sql(%(#{quoted_table_name}."recorded_at" ASC, #{quoted_table_name}."hid" ASC)))
        end

        # Fetches the given +object+ history, sorted by history record time
        # by default. Always includes an "as_of_time" column that is either
        # the upper bound of the validity range or now() if history validity
        # is maximum.
        #
        def of(object)
          where(id: object)
        end

        # The `sti_name` method returns the contents of the inheritance
        # column, and it is usually the class name. The inherited class
        # name has the "::History" suffix but that is never going to be
        # present in the data.
        #
        # As such it is overridden here to return the same contents that
        # the parent would have returned.
        delegate :sti_name, to: :superclass

        # For STI to work, the history model needs to have the exact same
        # semantics as the model it inherits from. However given it is
        # actually inherited, the original AR implementation would return
        # false here. But for STI sake, the history model is located in the
        # same exact hierarchy location as its parent, thus this is defined in
        # this override.
        #
        delegate :descends_from_active_record?, to: :superclass

        private

        # STI fails when a Foo::History record has Foo as type in the
        # inheritance column; AR expects the type to be an instance of the
        # current class or a descendant (or self).
        #
        def find_sti_class(type_name)
          super("#{type_name}::History")
        end
      end

      # The history id is `hid`, but this cannot set as primary key
      # or temporal associations will break. Solutions are welcome.
      def id
        hid
      end

      # Referenced record ID.
      #
      def rid
        attributes[self.class.primary_key]
      end

      def save(*)
        with_hid_pkey { super }
      end

      def save!(*)
        with_hid_pkey { super }
      end

      def update_columns(*)
        with_hid_pkey { super }
      end

      def historical?
        true
      end

      # Returns the previous history entry, or nil if this
      # is the first one.
      #
      def pred
        return if valid_from.nil?

        if self.class.timeline_associations.empty?
          self.class.where('id = ? AND upper(validity) = ?', rid, valid_from).first
        else
          super(id: rid, before: valid_from, table: self.class.superclass.quoted_table_name)
        end
      end

      # Returns the next history entry, or nil if this is the
      # last one.
      #
      def succ
        return if valid_to.nil?

        if self.class.timeline_associations.empty?
          self.class.where('id = ? AND lower(validity) = ?', rid, valid_to).first
        else
          super(id: rid, after: valid_to, table: self.class.superclass.quoted_table_name)
        end
      end
      alias next succ

      # Returns the first history entry
      #
      def first
        self.class.where(id: rid).chronological.first
      end

      # Returns the last history entry
      #
      def last
        self.class.where(id: rid).chronological.last
      end

      # Returns this history entry's current record
      #
      def current_version
        self.class.superclass.find(rid)
      end

      # Return `nil` instead of -Infinity/Infinity to preserve current
      # Chronomodel behaviour and avoid failures with Rails 7.0 and
      # unbounded time ranges
      #
      # Check if `begin` and `end` are `Time` because validity is a `tsrange`
      # column, so it is either `Time`, `nil`, and in some cases Infinity.
      #
      # Ref: rails/rails#45099
      # TODO: consider removing when Rails 7.0 support will be dropped
      def valid_from
        validity.begin if validity.begin.is_a?(Time)
      end

      def valid_to
        validity.end if validity.end.is_a?(Time)
      end

      # Computes an `as_of_time` strictly inside this record's validity period
      # for historical queries.
      #
      # Ensures association queries return versions that existed during this
      # record's validity, not ones that became valid exactly at the boundary
      # time. When objects are updated in the same transaction, they can share
      # the same `valid_to`, which would otherwise cause boundary
      # mis-selection.
      #
      # PostgreSQL ranges are half-open `[start, end)` by default.
      #
      # @return [Time, nil] `valid_to - ChronoModel::VALIDITY_TSRANGE_PRECISION`
      #   when `valid_to` is a Time; otherwise returns `valid_to` unchanged
      #   (which may be `nil` for open-ended validity).
      #
      # @see https://github.com/ifad/chronomodel/issues/283
      def as_of_time
        if valid_to.is_a?(Time)
          valid_to - ChronoModel::VALIDITY_TSRANGE_PRECISION
        else
          valid_to
        end
      end

      # `.read_attribute` uses the memoized `primary_key` if it detects
      # that the attribute name is `id`.
      #
      # Since the `primary key` may have been changed to `hid` because of
      # `.find` overload, the new behavior may break relations where `id` is
      # still the correct attribute to read
      #
      # Ref: ifad/chronomodel#181
      def read_attribute(attr_name, &block)
        return super unless attr_name.to_s == 'id' && @primary_key.to_s == 'hid'

        _read_attribute('id', &block)
      end

      private

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
