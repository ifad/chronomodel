# frozen_string_literal: true

require 'chrono_model/time_machine/time_query'
require 'chrono_model/time_machine/timeline'
require 'chrono_model/time_machine/history_model'

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
        if Rails.version >= '7.0'
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
        else
          alias_method :descendants_with_history, :descendants

          alias_method :direct_descendants_with_history, :direct_descendants
          def direct_descendants
            direct_descendants_with_history.reject(&:history?)
          end
        end

        def descendants
          descendants_with_history.reject(&:history?)
        end

        # STI support.
        #
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
          unless subclass.name.nil?
            ChronoModel::TimeMachine.define_history_model_for(subclass)
          end
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
                                                 %w(id hid validity recorded_at)
      end

      def has_timeline(options)
        changes = options.delete(:changes)
        assocs  = history.has_timeline(options)

        attributes = changes.present? ?
          Array.wrap(changes) : assocs.map(&:name)

        attribute_names_for_history_changes.concat(attributes.map(&:to_s))
      end

      delegate :timeline_associations, to: :history
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

    # Delegates to +HistoryModel::ClassMethods.as_of+ to fetch this instance
    # as it was on +time+. Used both by +as_of+ and +as_of!+ for performance
    # reasons, to avoid a `rescue` (@lleirborras).
    #
    def _as_of(time)
      self.class.as_of(time).where(id: self.id)
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
      self.as_of_time.present?
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
        history.reverse_order.second
      else
        return nil unless (ts = pred_timestamp(options))

        order_clause = Arel.sql %[ LOWER(#{options[:table] || self.class.quoted_table_name}."validity") DESC ]

        self.class.as_of(ts).order(order_clause).find(options[:id] || id)
      end
    end

    # Returns the previous timestamp in this record's timeline. Includes
    # temporal associations.
    #
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
    def succ
      nil
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
  end
end
