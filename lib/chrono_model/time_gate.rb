module ChronoModel

  # Provides the TimeMachine API to non-temporal models that associate
  # temporal ones.
  #
  module TimeGate
    extend ActiveSupport::Concern

    module ClassMethods
      def as_of(time)
        time = Conversions.time_to_utc_string(time.utc) if time.kind_of? Time

        virtual_table = select(%[
          #{quoted_table_name}.*, #{connection.quote(time)}::timestamp AS "as_of_time"]
        ).to_sql

        as_of = all.from("(#{virtual_table}) #{quoted_table_name}")

        as_of.instance_variable_set(:@temporal, time)

        return as_of
      end

      include TimeMachine::HistoryMethods::Timeline
    end

    def as_of(time)
      self.class.as_of(time).where(:id => self.id).first!
    end

    def timeline
      self.class.timeline(self)
    end
  end

end
