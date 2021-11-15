module ChronoModel
  module TimeMachine

    module Timeline
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
          assocs.each do |ass|
            association_quoted_table_name = connection.quote_table_name(ass.table_name)
            # `join` first, then use `where`s
            relation =
              if ass.belongs_to?
                relation.joins("LEFT JOIN #{association_quoted_table_name} ON #{association_quoted_table_name}.#{ass.association_primary_key} = #{quoted_table_name}.#{ass.association_foreign_key}")
              else
                relation.joins("LEFT JOIN #{association_quoted_table_name} ON #{association_quoted_table_name}.#{ass.foreign_key} = #{quoted_table_name}.#{primary_key}")
              end
          end
        end

        relation = relation.
          order('ts ' << (options[:reverse] ? 'DESC' : 'ASC'))

        relation = relation.from(%["public".#{quoted_table_name}]) unless self.chrono?
        relation = relation.where(id: rid) if rid

        sql = "SELECT ts FROM ( #{relation.to_sql} ) AS foo WHERE ts IS NOT NULL"

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
