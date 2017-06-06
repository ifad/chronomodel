require 'active_record'

module ChronoModel

  module TimeMachine
    extend ActiveSupport::Concern

    include Patches::AsOfTimeHolder

    included do
      if table_exists? && !chrono?
        puts "WARNING: #{table_name} is not a temporal table. " \
          "Please use change_table :#{table_name}, :temporal => true"
      end

      history = TimeMachine.define_history_model_for(self)
      TimeMachine.chrono_models[table_name] = history

      class << self
        alias_method :direct_descendants_with_history, :direct_descendants
        def direct_descendants
          direct_descendants_with_history.reject(&:history?)
        end

        alias_method :descendants_with_history, :descendants
        def descendants
          descendants_with_history.reject(&:history?)
        end

        # STI support. TODO: more thorough testing
        #
        def inherited(subclass)
          super

          # Do not smash stack: as the below method is defining a
          # new anonymous class, without this check this leads to
          # infinite recursion.
          unless subclass.name.nil?
            TimeMachine.define_inherited_history_model_for(subclass)
          end
        end
      end
    end

    # Returns an Hash keyed by table name of ChronoModels
    #
    def self.chrono_models
      (@chrono_models ||= {})
    end

    def self.define_history_model_for(model)
      history = Class.new(model) do
        self.table_name = [Adapter::HISTORY_SCHEMA, model.table_name].join('.')

        extend TimeMachine::HistoryMethods

        scope :chronological, -> { order(:recorded_at, :hid) }

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

        # HACK. find() and save() require the real history ID. So we are
        # setting it now and ensuring to reset it to the original one after
        # execution completes.
        #
        def self.with_hid_pkey(&block)
          old = self.primary_key
          self.primary_key = :hid

          block.call
        ensure
          self.primary_key = old
        end

        def self.find(*)
          with_hid_pkey { super }
        end

        if RUBY_VERSION.to_f < 2.0
          # PLEASE UPDATE YOUR RUBY <3
          #
          def save_with_pkey(*)
            self.class.with_hid_pkey { save_without_pkey }
          end

          def save_with_pkey!(*)
            self.class.with_hid_pkey { save_without_pkey! }
          end

          alias_method_chain :save, :pkey
        else
          def save(*)
            self.class.with_hid_pkey { super }
          end

          def save!(*)
            self.class.with_hid_pkey { super }
          end
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
          self.class.where(:id => rid).order('lower(validity)').first
        end

        # Returns the last history entry
        #
        def last
          self.class.where(:id => rid).order('lower(validity)').last
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
          Conversions.string_to_utc_time attributes_before_type_cast['recorded_at']
        end
      end

      model.singleton_class.instance_eval do
        define_method(:history) { history }
      end

      history.singleton_class.instance_eval do
        define_method(:sti_name) { model.sti_name }
      end

      model.const_set :History, history

      return history
    end

    def self.define_inherited_history_model_for(subclass)
      # Define history model for the subclass
      history = Class.new(subclass.superclass.history)
      history.table_name = subclass.superclass.history.table_name

      # Override the STI name on the history subclass
      history.singleton_class.instance_eval do
        define_method(:sti_name) { subclass.sti_name }
      end

      # Return the subclass history via the .history method
      subclass.singleton_class.instance_eval do
        define_method(:history) { history }
      end

      # Define the History constant inside the subclass
      subclass.const_set :History, history

      history.instance_eval do
        # Monkey patch of ActiveRecord::Inheritance.
        # STI fails when a Foo::History record has Foo as type in the
        # inheritance column; AR expects the type to be an instance of the
        # current class or a descendant (or self).
        def find_sti_class(type_name)
          super(type_name + "::History")
        end
      end
    end

    # Returns a read-only representation of this record as it was +time+ ago.
    # Returns nil if no record is found.
    #
    def as_of(time)
      _as_of(time).first
    end

    # Returns a read-only representation of this record as it was +time+ ago.
    # Raises ActiveRecord::RecordNotFound if no record is found.
    #
    def as_of!(time)
      _as_of(time).first!
    end

    # Delegates to +HistoryMethods.as_of+ to fetch this instance as it was on
    # +time+. Used both by +as_of+ and +as_of!+ for performance reasons, to
    # avoid a `rescue` (@lleirborras).
    #
    def _as_of(time)
      self.class.as_of(time).where(:id => self.id)
    end
    protected :_as_of

    # Return the complete read-only history of this instance.
    #
    def history
      self.class.history.chronological.of(self)
    end

    # Returns an Array of timestamps for which this instance has an history
    # record. Takes temporal associations into account.
    #
    def timeline(options = {})
      self.class.history.timeline(self, options)
    end

    # Returns a boolean indicating whether this record is an history entry.
    #
    def historical?
      self.as_of_time.present? || self.kind_of?(self.class.history)
    end

    # Inhibit destroy of historical records
    #
    def destroy
      raise ActiveRecord::ReadOnlyRecord, 'Cannot delete historical records' if historical?
      super
    end

    # Returns the previous record in the history, or nil if this is the only
    # recorded entry.
    #
    def pred(options = {})
      if self.class.timeline_associations.empty?
        history.order('upper(validity) DESC').offset(1).first
      else
        return nil unless (ts = pred_timestamp(options))
        self.class.as_of(ts).order(%[ #{options[:table] || self.class.quoted_table_name}."hid" DESC ]).find(options[:id] || id)
      end
    end

    # Returns the previous timestamp in this record's timeline. Includes
    # temporal associations.
    #
    def pred_timestamp(options = {})
      if historical?
        options[:before] ||= as_of_time
        timeline(options.merge(:limit => 1, :reverse => true)).first
      else
        timeline(options.merge(:limit => 2, :reverse => true)).second
      end
    end

    # Returns the next record in the history timeline.
    #
    def succ(options = {})
      unless self.class.timeline_associations.empty?
        return nil unless (ts = succ_timestamp(options))
        self.class.as_of(ts).order(%[ #{options[:table] || self.class.quoted_table_name}."hid" DESC ]).find(options[:id] || id)
      end
    end

    # Returns the next timestamp in this record's timeline. Includes temporal
    # associations.
    #
    def succ_timestamp(options = {})
      return nil unless historical?

      options[:after] ||= as_of_time
      timeline(options.merge(:limit => 1, :reverse => false)).first
    end

    # Returns the current history version
    #
    def current_version
      self.historical? ? self.class.find(self.id) : self
    end

    # Returns the differences between this entry and the previous history one.
    # See: +changes_against+.
    #
    def last_changes
      pred = self.pred
      changes_against(pred) if pred
    end

    # Returns the differences between this record and an arbitrary reference
    # record. The changes representation is an hash keyed by attribute whose
    # values are arrays containing previous and current attributes values -
    # the same format used by ActiveModel::Dirty.
    #
    def changes_against(ref)
      self.class.attribute_names_for_history_changes.inject({}) do |changes, attr|
        old, new = ref.public_send(attr), self.public_send(attr)

        changes.tap do |c|
          changed = old.respond_to?(:history_eql?) ?
            !old.history_eql?(new) : old != new

          c[attr] = [old, new] if changed
        end
      end
    end

    module ClassMethods
      # Identify this class as the parent, non-history, class.
      #
      def history?
        false
      end

      # Returns an ActiveRecord::Relation on the history of this model as
      # it was +time+ ago.
      def as_of(time)
        history.as_of(time)
      end

      def attribute_names_for_history_changes
        @attribute_names_for_history_changes ||= attribute_names -
          %w( id hid validity recorded_at )
      end

      def has_timeline(options)
        changes = options.delete(:changes)
        assocs  = history.has_timeline(options)

        attributes = changes.present? ?
          Array.wrap(changes) : assocs.map(&:name)

        attribute_names_for_history_changes.concat(attributes.map(&:to_s))
      end

      delegate :timeline_associations, :to => :history
    end

    module TimeQuery
      # TODO Documentation
      #
      def time_query(match, time, options)
        range = columns_hash.fetch(options[:on].to_s)

        query = case match
        when :at
          build_time_query_at(time, range)

        when :not
          "NOT (#{build_time_query_at(time, range)})"

        when :before
          op = options.fetch(:inclusive, true) ? '&&' : '@>'
          build_time_query(['NULL', time_for_time_query(time, range)], range, op)

        when :after
          op = options.fetch(:inclusive, true) ? '&&' : '@>'
          build_time_query([time_for_time_query(time, range), 'NULL'], range, op)

        else
          raise ArgumentError, "Invalid time_query: #{match}"
        end

        where(query)
      end

      private

        def time_for_time_query(t, column)
          if t == :now || t == :today
            now_for_column(column)
          else
            quoted_t = connection.quote(connection.quoted_date(t))
            [quoted_t, primitive_type_for_column(column)].join('::')
          end
        end

        def now_for_column(column)
          case column.type
          when :tsrange, :tstzrange then "timezone('UTC', current_timestamp)"
          when :daterange           then "current_date"
          else raise "Cannot generate 'now()' for #{column.type} column #{column.name}"
          end
        end

        def primitive_type_for_column(column)
          case column.type
          when :tsrange   then :timestamp
          when :tstzrange then :timestamptz
          when :daterange then :date
          else raise "Don't know how to map #{column.type} column #{column.name} to a primitive type"
          end
        end

        def build_time_query_at(time, range)
          time = if time.kind_of?(Array)
            time.map! {|t| time_for_time_query(t, range)}

            # If both edges of the range are the same the query fails using the '&&' operator.
            # The correct solution is to use the <@ operator.
            time.first == time.last ? time.first : time
          else
            time_for_time_query(time, range)
          end

          build_time_query(time, range)
        end

        def build_time_query(time, range, op = '&&')
          if time.kind_of?(Array)
            %[ #{range.type}(#{time.first}, #{time.last}) #{op} #{table_name}.#{range.name} ]
          else
            %[ #{time} <@ #{table_name}.#{range.name} ]
          end
        end
    end

    # Methods that make up the history interface of the companion History
    # model, automatically built for each Model that includes TimeMachine
    module HistoryMethods
      include TimeQuery

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
        all.order(%[ #{quoted_table_name}."recorded_at", #{quoted_table_name}."hid" ])
      end

      # Fetches the given +object+ history, sorted by history record time
      # by default. Always includes an "as_of_time" column that is either
      # the upper bound of the validity range or now() if history validity
      # is maximum.
      #
      def of(object)
        where(:id => object)
      end

      # FIXME Remove, this was a workaround to a former design flaw.
      #
      #   - vjt  Wed Oct 28 17:13:57 CET 2015
      #
      def force_history_fields
        self
      end

      include(Timeline = Module.new do
        # Returns an Array of unique UTC timestamps for which at least an
        # history record exists. Takes temporal associations into account.
        #
        def timeline(record = nil, options = {})
          rid = record.respond_to?(:rid) ? record.rid : record.id if record

          assocs = options.key?(:with) ?
            timeline_associations_from(options[:with]) : timeline_associations

          models = []
          models.push self if self.chrono?
          models.concat(assocs.map {|a| a.klass.history})

          return [] if models.empty?

          fields = models.inject([]) {|a,m| a.concat m.quoted_history_fields}

          relation = self.except(:order).
            select("DISTINCT UNNEST(ARRAY[#{fields.join(',')}]) AS ts")

          if assocs.present?
            relation = relation.joins(*assocs.map(&:name))
          end

          relation = relation.
            order('ts ' << (options[:reverse] ? 'DESC' : 'ASC'))

          relation = relation.from(%["public".#{quoted_table_name}]) unless self.chrono?
          relation = relation.where(:id => rid) if rid

          sql = "SELECT ts FROM ( #{relation.to_sql} ) foo WHERE ts IS NOT NULL"

          if options.key?(:before)
            sql << " AND ts < '#{Conversions.time_to_utc_string(options[:before])}'"
          end

          if options.key?(:after)
            sql << " AND ts > '#{Conversions.time_to_utc_string(options[:after ])}'"
          end

          if rid && !options[:with]
            sql << (self.chrono? ? %{
              AND ts <@ ( SELECT tsrange(min(lower(validity)), max(upper(validity)), '[]') FROM #{quoted_table_name} WHERE id = #{rid} )
            } : %[ AND ts < NOW() ])
          end

          sql << " LIMIT #{options[:limit].to_i}" if options.key?(:limit)

          sql.gsub! 'INNER JOIN', 'LEFT OUTER JOIN'

          connection.on_schema(Adapter::HISTORY_SCHEMA) do
            connection.select_values(sql, "#{self.name} periods").map! do |ts|
              Conversions.string_to_utc_time ts
            end
          end
        end

        def has_timeline(options)
          options.assert_valid_keys(:with)

          timeline_associations_from(options[:with]).tap do |assocs|
            timeline_associations.concat assocs
          end
        end

        def timeline_associations
          @timeline_associations ||= []
        end

        def timeline_associations_from(names)
          Array.wrap(names).map do |name|
            reflect_on_association(name) or raise ArgumentError,
              "No association found for name `#{name}'"
          end
        end
      end)

      def quoted_history_fields
        @quoted_history_fields ||= begin
          validity =
            [connection.quote_table_name(table_name),
             connection.quote_column_name('validity')
            ].join('.')

          [:lower, :upper].map! {|func| "#{func}(#{validity})"}
        end
      end
    end
  end

end
