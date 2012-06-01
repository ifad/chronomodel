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

      TimeMachine.chrono_models[table_name] = self
    end

    # Returns an Hash keyed by table name of models that included
    # ChronoModel::TimeMachine
    #
    def self.chrono_models
      (@chrono_models ||= {})
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

        readonly.with(table_name, on_history(time)).tap do |relation|
          relation.instance_variable_set(:@temporal, time)
        end
      end

      def on_history(time)
        unscoped.from(history_table_name).
          select("#{history_table_name}.*, '#{time}' AS as_of_time").
          where("'#{time}' >= valid_from AND '#{time}' < valid_to")
      end

      # Returns the whole history as read only.
      #
      def history
        readonly.from(history_table_name).order("#{history_table_name}.recorded_at")
      end

      # Fetches the given +object+ history, sorted by history record time.
      #
      def history_of(object)
        history.where(:id => object)
      end

      # Returns this table name in the +Adapter::HISTORY_SCHEMA+
      #
      def history_table_name
        [Adapter::HISTORY_SCHEMA, table_name].join('.')
      end
    end

    module QueryMethods
      def build_arel
        super.tap do |arel|

          # Extract joined tables and add temporal WITH if appropriate
          arel.join_sources.map {|j| j.to_sql =~ /JOIN "(\w+)" ON/ && $1}.compact.each do |table|
            next unless (model = TimeMachine.chrono_models[table])
            with(table, model.on_history(@temporal))
          end if @temporal

        end
      end
    end
    ActiveRecord::Relation.instance_eval { include QueryMethods }

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
