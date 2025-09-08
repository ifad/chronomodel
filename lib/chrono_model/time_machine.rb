# frozen_string_literal: true

require_relative 'time_machine/time_query'
require_relative 'time_machine/timeline'
require_relative 'time_machine/history_model'

module ChronoModel
  module TimeMachine
    include ChronoModel::Patches::AsOfTimeHolder

    extend ActiveSupport::Concern

    included do
      if table_exists? && !chrono?
        logger.warn <<-MSG.squish
          ChronoModel: #{table_name} is not a temporal table.
          Please use `change_table :#{table_name}, temporal: true` in a migration.
        MSG
      end

      history = ChronoModel::TimeMachine.define_history_model_for(self)
      ChronoModel.history_models[table_name] = history

      class << self
        def subclasses(with_history: false)
          subclasses = super()
          subclasses.reject!(&:history?) unless with_history
          subclasses
        end

        def subclasses_with_history
          subclasses(with_history: true)
        end

        # `direct_descendants` is deprecated method in 7.0 and has been
        # removed in 7.1
        if method_defined?(:direct_descendants)
          alias_method :direct_descendants_with_history, :subclasses_with_history
          alias_method :direct_descendants, :subclasses
        end

        # Ruby 3.1 has a native subclasses method and descendants is
        # implemented with recursion of subclasses
        if Class.method_defined?(:subclasses)
          def descendants_with_history
            subclasses_with_history.concat(subclasses.flat_map(&:descendants_with_history))
          end
        end

        def descendants
          descendants_with_history.reject(&:history?)
        end

        # Handles Single Table Inheritance support for temporal models.
        #
        # @param subclass [Class] the inheriting class
        # @return [void]
        def inherited(subclass)
          super

          # Do not smash stack. The below +define_history_model_for+ method
          # defines a new inherited class via Class.new(), thus +inherited+
          # is going to be called again. By that time the subclass is still
          # an anonymous one, so its +name+ method returns nil. We use this
          # condition to avoid infinite recursion.
          #
          # Sadly, we can't avoid it by calling +.history?+, because in the
          # subclass the HistoryModel hasn't been included yet.
          #
          return if subclass.name.nil?

          ChronoModel::TimeMachine.define_history_model_for(subclass)
        end
      end
    end

    def self.define_history_model_for(model)
      history = Class.new(model) do
        include ChronoModel::TimeMachine::HistoryModel
      end

      model.singleton_class.instance_eval do
        define_method(:history) { history }
      end

      model.const_set :History, history
    end

    module ClassMethods
      # Identifies this class as the parent, non-history, class.
      #
      # @return [Boolean] always returns false for non-history models
      def history?
        false
      end

      # Returns an ActiveRecord::Relation on the history of this model as
      # it was +time+ ago.
      delegate :as_of, to: :history

      def attribute_names_for_history_changes
        @attribute_names_for_history_changes ||= attribute_names -
                                                 %w[id hid validity recorded_at]
      end

      def has_timeline(options)
        changes = options.delete(:changes)
        assocs  = history.has_timeline(options)

        attributes =
          if changes.present?
            Array.wrap(changes)
          else
            assocs.map(&:name)
          end

        attribute_names_for_history_changes.concat(attributes.map(&:to_s))
      end

      delegate :timeline_associations, to: :history
    end

    # Returns a read-only representation of this record as it was at the given time.
    # Returns nil if no record is found.
    #
    # @param time [Time, DateTime] the time to query for
    # @return [Object, nil] the historical record or nil if not found
    def as_of(time)
      _as_of(time).first
    end

    # Returns a read-only representation of this record as it was at the given time.
    # Raises ActiveRecord::RecordNotFound if no record is found.
    #
    # @param time [Time, DateTime] the time to query for
    # @return [Object] the historical record
    # @raise [ActiveRecord::RecordNotFound] if no record is found at that time
    def as_of!(time)
      _as_of(time).first!
    end

    # Delegates to +HistoryModel::ClassMethods.as_of+ to fetch this instance
    # as it was on +time+. Used both by +as_of+ and +as_of!+ for performance
    # reasons, to avoid a `rescue` (@lleirborras).
    #
    # @param time [Time, DateTime] the time to query for
    # @return [ActiveRecord::Relation] the scoped history relation
    # @api private
    def _as_of(time)
      self.class.as_of(time).where(id: id)
    end
    protected :_as_of

    # Returns the complete read-only history of this instance.
    #
    # @return [ActiveRecord::Relation] chronologically ordered history records
    def history
      self.class.history.chronological.of(self)
    end

    # Returns an Array of timestamps for which this instance has an history
    # record. Takes temporal associations into account.
    #
    # @param options [Hash] timeline options
    # @return [Array<Time>] array of timestamps
    def timeline(options = {})
      self.class.history.timeline(self, options)
    end

    # Returns a boolean indicating whether this record is an history entry.
    #
    # @return [Boolean] true if this is a historical record, false otherwise
    def historical?
      as_of_time.present?
    end

    # Inhibits destroy of historical records.
    #
    # @return [void]
    # @raise [ActiveRecord::ReadOnlyRecord] if attempting to destroy a historical record
    def destroy
      raise ActiveRecord::ReadOnlyRecord, 'Cannot delete historical records' if historical?

      super
    end

    # Returns the previous record in the history, or nil if this is the only
    # recorded entry.
    #
    # @param options [Hash] options for the query
    # @return [Object, nil] the previous historical record or nil
    def pred(options = {})
      if self.class.timeline_associations.empty?
        history.reverse_order.second
      else
        return nil unless (ts = pred_timestamp(options))

        order_clause = Arel.sql %[LOWER(#{options[:table] || self.class.quoted_table_name}."validity") DESC]

        self.class.as_of(ts).order(order_clause).find(options[:id] || id)
      end
    end

    # Returns the previous timestamp in this record's timeline. Includes
    # temporal associations.
    #
    # @param options [Hash] options for the timeline query
    # @return [Time, nil] the previous timestamp or nil if not found
    def pred_timestamp(options = {})
      if historical?
        options[:before] ||= as_of_time
        timeline(options.merge(limit: 1, reverse: true)).first
      else
        timeline(options.merge(limit: 2, reverse: true)).second
      end
    end

    # This is a current record, so its next instance is always nil.
    #
    # @return [nil] always returns nil for current records
    def succ
      nil
    end

    # Returns the current history version.
    #
    # @return [Object] the current version of this record
    def current_version
      if historical?
        self.class.find(id)
      else
        self
      end
    end

    # Returns the differences between this entry and the previous history one.
    # See: +changes_against+.
    #
    # @return [Hash, nil] hash of changes or nil if no previous record exists
    def last_changes
      pred = self.pred
      changes_against(pred) if pred
    end

    # Returns the differences between this record and an arbitrary reference
    # record. The changes representation is an hash keyed by attribute whose
    # values are arrays containing previous and current attributes values -
    # the same format used by ActiveModel::Dirty.
    #
    # @param ref [Object] the reference record to compare against
    # @return [Hash] hash of changes in ActiveModel::Dirty format
    def changes_against(ref)
      self.class.attribute_names_for_history_changes.inject({}) do |changes, attr|
        old = ref.public_send(attr)
        new = public_send(attr)

        changes.tap do |c|
          changed =
            if old.respond_to?(:history_eql?)
              !old.history_eql?(new)
            else
              old != new
            end

          c[attr] = [old, new] if changed
        end
      end
    end
  end
end
