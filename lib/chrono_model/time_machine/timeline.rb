# frozen_string_literal: true

module ChronoModel
  module TimeMachine
    # Provides timeline functionality for temporal models and their associations.
    #
    # This module enables querying unique timestamps across temporal models and their
    # associated temporal models, providing comprehensive timeline functionality.
    module Timeline
      # Returns an Array of unique UTC timestamps for which at least an
      # history record exists. Takes temporal associations into account.
      #
      # @param record [ActiveRecord::Base, Integer, nil] the record or record ID to get timeline for
      # @param options [Hash] timeline query options
      # @option options [Array<Symbol>, Symbol] :with associations to include in timeline
      # @option options [Boolean] :reverse whether to sort timestamps in descending order
      # @option options [Time] :before only include timestamps before this time
      # @option options [Time] :after only include timestamps after this time
      # @option options [Integer] :limit maximum number of timestamps to return
      # @return [Array<Time>] array of unique UTC timestamps
      def timeline(record = nil, options = {})
        rid =
          if record
            if record.respond_to?(:rid)
              record.rid
            else
              record.id
            end
          end

        assocs =
          if options.key?(:with)
            timeline_associations_from(options[:with])
          else
            timeline_associations
          end

        models = []
        models.push self if chrono?
        models.concat(assocs.map { |a| a.klass.history })

        return [] if models.empty?

        fields = models.inject([]) { |a, m| a.concat m.quoted_history_fields }

        relation = except(:order)
                   .select("DISTINCT UNNEST(ARRAY[#{fields.join(',')}]) AS ts")

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

        relation_order =
          if options[:reverse]
            'DESC'
          else
            'ASC'
          end

        relation = relation.order("ts #{relation_order}")

        relation = relation.from("public.#{quoted_table_name}") unless chrono?
        relation = relation.where(id: rid) if rid

        sql = "SELECT ts FROM (#{relation.to_sql}) AS foo WHERE ts IS NOT NULL"

        if options.key?(:before)
          sql << " AND ts < '#{Conversions.time_to_utc_string(options[:before])}'"
        end

        if options.key?(:after)
          sql << " AND ts > '#{Conversions.time_to_utc_string(options[:after])}'"
        end

        if rid && !options[:with]
          sql <<
            if chrono?
              %{ AND ts <@ (SELECT tsrange(min(lower(validity)), max(upper(validity)), '[]') FROM #{quoted_table_name} WHERE id = #{rid})}
            else
              ' AND ts < NOW()'
            end
        end

        sql << " LIMIT #{options[:limit].to_i}" if options.key?(:limit)

        connection.on_schema(Adapter::HISTORY_SCHEMA) do
          connection.select_values(sql, "#{name} periods")
        end
      end

      # Configures timeline associations for this model.
      #
      # @param options [Hash] configuration options
      # @option options [Array<Symbol>, Symbol] :with association names to include in timeline
      # @return [Array<ActiveRecord::Reflection::AssociationReflection>] configured associations
      def has_timeline(options)
        options.assert_valid_keys(:with)

        timeline_associations_from(options[:with]).tap do |assocs|
          timeline_associations.concat assocs
        end
      end

      # Returns the timeline associations configured for this model.
      #
      # @return [Array<ActiveRecord::Reflection::AssociationReflection>] timeline associations
      def timeline_associations
        @timeline_associations ||= []
      end

      # Converts association names to association reflection objects.
      #
      # @param names [Array<Symbol>, Symbol] association names
      # @return [Array<ActiveRecord::Reflection::AssociationReflection>] association reflections
      # @raise [ArgumentError] if an association is not found
      def timeline_associations_from(names)
        Array.wrap(names).map do |name|
          reflect_on_association(name) or raise ArgumentError,
                                                "No association found for name `#{name}'"
        end
      end

      # Returns quoted history field names for this model's timeline.
      #
      # @return [Array<String>] array of quoted SQL field expressions for timeline queries
      def quoted_history_fields
        @quoted_history_fields ||= begin
          validity = "#{quoted_table_name}.#{connection.quote_column_name('validity')}"

          %w[lower upper].map! { |func| "#{func}(#{validity})" }
        end
      end
    end
  end
end
