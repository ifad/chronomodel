module ChronoModel
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    module TSRange
      # HACK: Redefine tsrange parsing support, as it is broken currently.
      #
      # This self-made API is here because currently AR4 does not support
      # open-ended ranges. The reasons are poor support in Ruby:
      #
      #   https://bugs.ruby-lang.org/issues/6864
      #
      # and an instable interface in Active Record:
      #
      #   https://github.com/rails/rails/issues/13793
      #   https://github.com/rails/rails/issues/14010
      #
      # so, for now, we are implementing our own.
      #
      class Type < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Range
        OID = 3908

        def cast_value(value)
          return if value == 'empty'
          return value if value.is_a?(::Array)

          extracted = extract_bounds(value)

          from = Conversions.string_to_utc_time extracted[:from]
          to   = Conversions.string_to_utc_time extracted[:to]

          [from, to]
        end

        def extract_bounds(value)
          from, to = value[1..-2].split(',')
          {
            from: value[1] == ',' || from == '-infinity' ? nil : from[1..-2],
            to: value[-2] == ',' || to == 'infinity' ? nil : to[1..-2],
          }
        end
      end

      def initialize_type_map(m = type_map)
        super.tap do
          typ = ChronoModel::Adapter::TSRange::Type
          oid = typ::OID

          ar_type = type_map.fetch(oid)
          cm_type = typ.new(ar_type.subtype, ar_type.type)

          type_map.register_type oid, cm_type
        end
      end
    end
  end
end
