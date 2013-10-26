require 'active_record'

module ChronoModel

  module TimeMachine
    extend ActiveSupport::Concern

    included do
      unless supports_chrono?
        raise Error, "Your database server is not supported by ChronoModel. "\
          "Currently, only PostgreSQL >= 9.0 is supported."
      end

      if table_exists? && !chrono?
        puts "WARNING: #{table_name} is not a temporal table. " \
          "Please use change_table :#{table_name}, :temporal => true"
      end

      history = TimeMachine.define_history_model_for(self)
      TimeMachine.chrono_models[table_name] = history

      # STI support. TODO: more thorough testing
      #
      def self.inherited(subclass)
        super

        # Do not smash stack: as the below method is defining a
        # new anonymous class, without this check this leads to
        # infinite recursion.
        unless subclass.name.nil?
          TimeMachine.define_inherited_history_model_for(subclass)
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

        # The history id is `hid`, but this cannot set as primary key
        # or temporal assocations will break. Solutions are welcome.
        def id
          hid
        end

        # Referenced record ID
        #
        def rid
          attributes[self.class.primary_key]
        end

        # HACK to make ActiveAdmin work properly. This will be surely
        # better written in the future.
        #
        def self.find(*args)
          old = self.primary_key
          self.primary_key = :hid
          super
        ensure
          self.primary_key = old
        end

        # Returns the previous history entry, or nil if this
        # is the first one.
        #
        def pred
          return nil if self.valid_from.year.zero?

          if self.class.timeline_associations.empty?
            self.class.where(:id => rid, :valid_to => valid_from_before_type_cast).first
          else
            super(:id => rid, :before => valid_from)
          end
        end

        # Returns the next history entry, or nil if this is the
        # last one.
        #
        def succ
          return nil if self.valid_to.year == 9999

          if self.class.timeline_associations.empty?
            self.class.where(:id => rid, :valid_from => valid_to_before_type_cast).first
          else
            super(:id => rid, :after => valid_to)
          end
        end
        alias :next :succ

        # Returns the first history entry
        #
        def first
          self.class.where(:id => rid).order(:valid_from).first
        end

        # Returns the last history entry
        #
        def last
          self.class.where(:id => rid).order(:valid_from).last
        end

        # Returns this history entry's current record
        #
        def record
          self.class.superclass.find(rid)
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
      self.class.history.of(self)
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
      self.attributes.key?('as_of_time') || self.kind_of?(self.class.history)
    end

    # Hack around AR timezone support. These timestamps are recorded
    # by the chrono rewrite rules in UTC, but AR reads them as they
    # were stored in the local timezone - thus here we bypass type
    # casting to force creation of UTC timestamps.
    #
    %w( valid_from valid_to recorded_at as_of_time ).each do |attr|
      define_method(attr) do
        Conversions.string_to_utc_time attributes_before_type_cast[attr]
      end
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
        history.order('valid_to DESC').offset(1).first
      else
        return nil unless (ts = pred_timestamp(options))
        self.class.as_of(ts).order('hid desc').find(options[:id] || id)
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
        self.class.as_of(ts).order('hid desc').find(options[:id] || id)
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

    # Wraps AR::Base#attributes by removing the __xid internal attribute
    # used to squash together changes made in the same transaction.
    #
    %w( attributes attribute_names ).each do |name|
      define_method(name) { super().tap {|x| x.delete('__xid')} }
    end

    module ClassMethods
      # Returns an ActiveRecord::Relation on the history of this model as
      # it was +time+ ago.
      def as_of(time)
        history.as_of(time, current_scope)
      end

      def attribute_names_for_history_changes
        @attribute_names_for_history_changes ||= attribute_names -
          %w( id hid valid_from valid_to recorded_at as_of_time )
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
      OPERATORS = {
        :at      => '&&',
        :before  => '<<',
        :after   => '>>',
      }.freeze

      def time_query(match, time_or_times, options)
        from_f, to_f = options[:on]

        from_t, to_t = if time_or_times.kind_of?(Array)
          time_or_times.map! {|t| time_for_time_query(t)}
        else
          [time_for_time_query(time_or_times)]*2
        end

        if match == :not
          where(%[
            #{build_time_query(:before, from_t, from_f, to_t, to_f)} OR
            #{build_time_query(:after,  from_t, from_f, to_t, to_f)}
          ])
        else
          where(build_time_query(match, from_t, from_f, to_t, to_f))
        end
      end

      private
        def time_for_time_query(t)
          t = Conversions.time_to_utc_string(t.utc) if t.kind_of?(Time)
          t == :now ? 'now()' : "#{connection.quote(t)}::timestamp"
        end

        def build_time_query(match, from_t, from_f, to_t, to_f)
          %[
            box(
              point( date_part( 'epoch', #{from_f} ), 0 ),
              point( date_part( 'epoch', #{to_f  } ), 0 )
            ) #{OPERATORS.fetch(match)}
            box(
              point( date_part( 'epoch', #{from_t} ), 0 ),
              point( date_part( 'epoch', #{to_t  } ), 0 )
            )
          ]
        end
    end

    # Methods that make up the history interface of the companion History
    # model, automatically built for each Model that includes TimeMachine
    module HistoryMethods
      include TimeQuery

      # for identifying this class as the History subclass
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
        if klass.superclass.respond_to?(:history?) && klass.superclass.history?
          non_history_superclass(klass.superclass)
        else
          klass.superclass
        end
      end

      # Fetches as of +time+ records.
      #
      def as_of(time, scope = nil)
        as_of = non_history_superclass.unscoped.readonly.from(virtual_table_at(time))

        # Add default scopes back if we're passed nil or a
        # specific scope, because we're .unscopeing above.
        #
        scopes = !scope.nil? ? [scope] : (
          superclass.default_scopes.map do |s|
            s.respond_to?(:call) ? s.call : s
          end)

        scopes.each do |s|
          s.order_values.each {|clause| as_of = as_of.order(clause)}
          s.where_values.each {|clause| as_of = as_of.where(clause)}
        end

        as_of.instance_variable_set(:@temporal, time)

        return as_of
      end

      def virtual_table_at(time, name = nil)
        name = name ? connection.quote_table_name(name) :
          non_history_superclass.quoted_table_name

        "(#{at(time).to_sql}) #{name}"
      end

      # Fetches history record at the given time
      #
      def at(time)
        time = Conversions.time_to_utc_string(time.utc) if time.kind_of?(Time)

        unscoped.
          select("#{quoted_table_name}.*, #{connection.quote(time)} AS as_of_time").
          time_query(:at, time, :on => quoted_history_fields)
      end

      # Returns the whole history as read only.
      #
      def all
        readonly.
          order("#{quoted_table_name}.recorded_at, hid").all
      end

      # Fetches the given +object+ history, sorted by history record time
      # by default. Always includes an "as_of_time" column that is either
      # the valid_to timestamp or now() if history validity is maximum.
      #
      def of(object)
        readonly.where(:id => object).extend(HistorySelect)
      end

      module HistorySelect #:nodoc:
        Aggregates = %r{(?:(?:bit|bool)_(?:and|or)|(?:array_|string_|xml)agg|count|every|m(?:in|ax)|sum|stddev|var(?:_pop|_samp|iance)|corr|covar_|regr_)\w*\s*\(}i

        def build_arel
          has_aggregate = select_values.any? do |v|
            v.kind_of?(Arel::Nodes::Function) || # FIXME this is a bit ugly.
            v.to_s =~ Aggregates
          end

          return super if has_aggregate

          if order_values.blank?
            self.order_values += ["#{quoted_table_name}.recorded_at, #{quoted_table_name}.hid"]
          end

          super.tap do |rel|
            rel.project("LEAST(valid_to, now()::timestamp) AS as_of_time")
          end
        end
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
          fields.map! {|f| "#{f} + INTERVAL '2 usec'"}

          relation = self.
            joins(*assocs.map(&:name)).
            select("DISTINCT UNNEST(ARRAY[#{fields.join(',')}]) AS ts").
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

          if rid
            sql << (self.chrono? ? %[
              AND ts >= ( SELECT MIN(valid_from) FROM #{quoted_table_name} WHERE id = #{rid} )
              AND ts <  ( SELECT MAX(valid_to  ) FROM #{quoted_table_name} WHERE id = #{rid} )
            ] : %[ AND ts < NOW() ])
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
        @quoted_history_fields ||= [:valid_from, :valid_to].map do |field|
          [connection.quote_table_name(table_name),
           connection.quote_column_name(field)
          ].join('.')
        end
      end
    end

    module QueryMethods
      def build_arel
        super.tap do |arel|

          arel.join_sources.each do |join|
            model = TimeMachine.chrono_models[join.left.table_name]
            next unless model

            join.left = Arel::Nodes::SqlLiteral.new(
              model.history.virtual_table_at(@temporal, join.left.table_alias || join.left.table_name)
            )
          end if @temporal

        end
      end
    end
    ActiveRecord::Relation.instance_eval { include QueryMethods }

  end

end
