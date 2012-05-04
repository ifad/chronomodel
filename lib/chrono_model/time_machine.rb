require 'active_record'

module ChronoModel

  module TimeMachine
    extend ActiveSupport::Concern

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

    module ClassMethods
      # Fetches as of +time+ records.
      #
      def as_of(time)
        on_history do
          where(':ts BETWEEN valid_from AND valid_to', :ts => time)
        end
      end

      # Fetches the given +object+ history, sorted by history record time.
      #
      def history_of(object)
        on_history do
          where(:id => object).order(history_field(:recorded_at))
        end
      end

      private
        # Assumes the block will return an ActiveRecord::Relation and
        # makes it fetch data from the +history_table+ in read-only mode.
        #
        def on_history(&block)
          block.call.readonly.from(history_table)
        end

        # Returns this table name in the +Adapter::HISTORY_SCHEMA+
        #
        def history_table
          [Adapter::HISTORY_SCHEMA, table_name].join('.')
        end

        # Returns the given field in the +history_table+.
        #
        def history_field(name)
          [history_table, name].join('.')
        end
    end

  end

end
