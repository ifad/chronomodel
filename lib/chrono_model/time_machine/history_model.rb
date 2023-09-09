module ChronoModel
  module TimeMachine
    module HistoryModel
      extend ActiveSupport::Concern

      included do
        self.table_name = [Adapter::HISTORY_SCHEMA, superclass.table_name].join('.')

        scope :chronological, -> { order(Arel.sql('lower(validity) ASC')) }
      end

      # ACTIVE RECORD 7 does not call `class.find` but a new internal method called `_find_record`
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
          old = self.primary_key
          self.primary_key = :hid

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
          virtual_name = table_name ?
            connection.quote_table_name(table_name) :
            superclass.quoted_table_name

          "(#{at(time).to_sql}) #{virtual_name}"
        end

        # Fetches history record at the given time
        #
        def at(time)
          time_query(:at, time).from(quoted_table_name).as_of_time!(time)
        end

        # Returns the history sorted by recorded_at
        #
        def sorted
          all.order(Arel.sql(%[ #{quoted_table_name}."recorded_at" ASC, #{quoted_table_name}."hid" ASC ]))
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
        # As such it is overriden here to return the same contents that
        # the parent would have returned.
        def sti_name
          superclass.sti_name
        end

        # For STI to work, the history model needs to have the exact same
        # semantics as the model it inherits from. However given it is
        # actually inherited, the original AR implementation would return
        # false here. But for STI sake, the history model is located in the
        # same exact hierarchy location as its parent, thus this is defined in
        # this override.
        #
        def descends_from_active_record?
          superclass.descends_from_active_record?
        end

        private

          # STI fails when a Foo::History record has Foo as type in the
          # inheritance column; AR expects the type to be an instance of the
          # current class or a descendant (or self).
          #
          def find_sti_class(type_name)
            super(type_name + "::History")
          end
      end

      # The history id is `hid`, but this cannot set as primary key
      # or temporal assocations will break. Solutions are welcome.
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
        return if self.valid_from.nil?

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
        return if self.valid_to.nil?

        if self.class.timeline_associations.empty?
          self.class.where('id = ? AND lower(validity) = ?', rid, valid_to).first
        else
          super(id: rid, after: valid_to, table: self.class.superclass.quoted_table_name)
        end
      end
      alias :next :succ

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

      def record #:nodoc:
        ActiveSupport::Deprecation.warn '.record is deprecated in favour of .current_version'
        self.current_version
      end

      def valid_from
        validity.first
      end

      def valid_to
        validity.last
      end
      alias as_of_time valid_to

      def recorded_at
        ChronoModel::Conversions.string_to_utc_time attributes_before_type_cast['recorded_at']
      end

      # Starting from Rails 6.0, `.read_attribute` will use the memoized
      # `primary_key` if it detects that the attribute name is `id`.
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

      def with_hid_pkey
        old_primary_key = @primary_key
        @primary_key = :hid

        self.class.with_hid_pkey { yield }
      ensure
        @primary_key = old_primary_key
      end
    end
  end
end
