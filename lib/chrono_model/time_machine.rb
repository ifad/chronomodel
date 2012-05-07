require 'active_record'

module ChronoModel

  module TimeMachine
    extend ActiveSupport::Concern

    included do
      unless supports_chrono?
        raise Error, "Your database server is not supported by ChronoModel. "\
          "Currently, only PostgreSQL >= 9.0 is supported."
      end

      unless chrono?
        raise Error, "#{table_name} is not a temporal table. " \
          "Please use change_table :#{table_name}, :temporal => true"
      end
    end

    # Returns a read-only representation of this record as it was +time+ ago.
    #
    def as_of(time)
      self.class.as_of(time).find(self)
    end

    # Return the complete read-only history of this instance.
    #
    def history
      self.class.history_of(self)
    end

    # Aborts the destroy if this is an historical record
    #
    def destroy
      if historical?
        raise ActiveRecord::ReadOnlyRecord, 'Cannot delete historical records'
      else
        super
      end
    end

    # Returns true if this record was fetched from history
    #
    def historical?
      hid.present?
    end

    HISTORY_ATTRIBUTES = %w( valid_from valid_to recorded_at as_of_time ).each do |attr|
      define_method(attr) { Conversions.string_to_utc_time(attributes[attr]) }
    end

    # Strips the history timestamps when duplicating history records
    #
    def initialize_dup(other)
      super

      if historical?
        HISTORY_ATTRIBUTES.each {|attr| @attributes.delete(attr)}
        @attributes.delete 'hid'
        @readonly = false
        @new_record = true
      end
    end

    module ClassMethods
      # Fetches as of +time+ records.
      #
      def as_of(time)
        time = Conversions.time_to_utc_string(time.utc)

        readonly.with(
          table_name, unscoped.
            select("#{history_table_name}.*, '#{time}' AS as_of_time").
            from(history_table_name).
            where("'#{time}' BETWEEN #{table_name}.valid_from AND #{table_name}.valid_to")
        )
      end

      # Fetches the given +object+ history, sorted by history record time.
      #
      def history_of(object)
        readonly.from(history_table_name).where(:id => object).order(history_field(:recorded_at))
      end

      # Returns this table name in the +Adapter::HISTORY_SCHEMA+
      #
      def history_table_name
        [Adapter::HISTORY_SCHEMA, table_name].join('.')
      end

      private
        # Returns the given field in the +history_table+.
        #
        def history_field(name)
          [history_table_name, name].join('.')
        end
    end

    module Conversions
      extend self

      ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d+)?\z/

      def string_to_utc_time(string)
        if string =~ ISO_DATETIME
          microsec = ($7.to_f * 1_000_000).to_i
          Time.utc $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, microsec
        end
      end

      def time_to_utc_string(time)
        [time.to_s(:db), sprintf('%06d', time.usec)].join '.'
      end
    end

  end

end
