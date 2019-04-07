module ChronoModel
  module TimeMachine

    module HistoryModel
      extend ActiveSupport::Concern

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
        def with_hid_pkey(&block)
          old = self.primary_key
          self.primary_key = :hid

          block.call
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

        # Getting the correct quoted_table_name can be tricky when
        # STI is involved. If Orange < Fruit, then Orange::History < Fruit::History
        # (see define_inherited_history_model_for).
        # This means that the superclass method returns Fruit::History, which
        # will give us the wrong table name. What we actually want is the
        # superclass of Fruit::History, which is Fruit. So, we use
        # non_history_superclass instead. -npj
        def non_history_superclass(klass = self)
          if klass.superclass.history?
            non_history_superclass(klass.superclass)
          else
            klass.superclass
          end
        end

        def relation
          super.as_of_time!(Time.now)
        end

        # Fetches as of +time+ records.
        #
        def as_of(time)
          non_history_superclass.from(virtual_table_at(time)).as_of_time!(time)
        end

        def virtual_table_at(time, name = nil)
          name = name ? connection.quote_table_name(name) :
            non_history_superclass.quoted_table_name

          "(#{at(time).to_sql}) #{name}"
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
          where(:id => object)
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
        self.class.with_hid_pkey { super }
      end

      def save!(*)
        self.class.with_hid_pkey { super }
      end

      def update_columns(*)
        self.class.with_hid_pkey { super }
      end

      # Returns the previous history entry, or nil if this
      # is the first one.
      #
      def pred
        return if self.valid_from.nil?

        if self.class.timeline_associations.empty?
          self.class.where('id = ? AND upper(validity) = ?', rid, valid_from).first
        else
          super(:id => rid, :before => valid_from, :table => self.class.superclass.quoted_table_name)
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
          super(:id => rid, :after => valid_to, :table => self.class.superclass.quoted_table_name)
        end
      end
      alias :next :succ

      # Returns the first history entry
      #
      def first
        self.class.where(:id => rid).chronological.first
      end

      # Returns the last history entry
      #
      def last
        self.class.where(:id => rid).chronological.last
      end

      # Returns this history entry's current record
      #
      def current_version
        self.class.non_history_superclass.find(rid)
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
    end

  end
end
