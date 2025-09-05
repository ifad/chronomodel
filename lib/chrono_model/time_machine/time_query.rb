# frozen_string_literal: true

module ChronoModel
  module TimeMachine
    #
    # TODO Documentation
    #
    module TimeQuery
      def time_query(match, time, options)
        range = columns_hash.fetch(options[:on].to_s)

        where(time_query_sql(match, time, range, options))
      end

      private

      def time_query_sql(match, time, range, options)
        case match
        when :at
          build_time_query_at(time, range)

        when :not
          "NOT (#{build_time_query_at(time, range)})"

        when :before
          op =
            if options.fetch(:inclusive, true)
              '&&'
            else
              '@>'
            end
          build_time_query(['NULL', time_for_time_query(time, range)], range, op)

        when :after
          op =
            if options.fetch(:inclusive, true)
              '&&'
            else
              '@>'
            end
          build_time_query([time_for_time_query(time, range), 'NULL'], range, op)

        else
          raise ChronoModel::Error, "Invalid time_query: #{match}"
        end
      end

      def time_for_time_query(t, column)
        case t
        when :now, :today
          now_for_column(column)
        else
          quoted_t = connection.quote(connection.quoted_date(t))
          "#{quoted_t}::#{primitive_type_for_column(column)}"
        end
      end

      def now_for_column(column)
        case column.type
        when :tsrange, :tstzrange then "timezone('UTC', current_timestamp)"
        when :daterange           then 'current_date'
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
        time =
          if time.is_a?(Array)
            time.map! { |t| time_for_time_query(t, range) }

            # If both edges of the range are the same the query fails using the '&&' operator.
            # The correct solution is to use the <@ operator.
            if time.first == time.last
              time.first
            else
              time
            end
          else
            time_for_time_query(time, range)
          end

        build_time_query(time, range)
      end

      def build_time_query(time, range, op = '&&')
        if time.is_a?(Array)
          Arel.sql %[#{range.type}(#{time.first}, #{time.last}) #{op} #{table_name}.#{range.name} ]
        else
          Arel.sql %(#{time} <@ #{table_name}.#{range.name})
        end
      end
    end
  end
end
