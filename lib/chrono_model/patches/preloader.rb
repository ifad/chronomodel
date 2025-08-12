# frozen_string_literal: true

module ChronoModel
  module Patches
    # Patches ActiveRecord::Associations::Preloader to add support for
    # temporal associations. This is tying itself to Rails internals
    # and it is ugly :-(.
    #
    module Preloader
      attr_reader :chronomodel_options

      # Overwrite the initializer to set Chronomodel +as_of_time+ and +model+
      # options.
      #
      def initialize(**options)
        @chronomodel_options = options.extract!(:as_of_time, :model)
        options[:scope] = chronomodel_scope(options[:scope]) if options.key?(:scope)

        super
      end

      private

      def chronomodel_scope(given_preload_scope)
        preload_scope = given_preload_scope

        if chronomodel_options[:as_of_time]
          preload_scope ||= ChronoModel::Patches::AsOfTimeRelation.new(chronomodel_options[:model])
          preload_scope.as_of_time!(chronomodel_options[:as_of_time])
        end

        preload_scope
      end

      module Association
        private

        # Builds the preloader scope taking into account a potential
        # +as_of_time+ passed down the call chain starting at the
        # end user invocation.
        #
        def build_scope
          scope = super

          if preload_scope.try(:as_of_time)
            scope = scope.as_of(preload_scope.as_of_time)
          end

          scope
        end
      end

      module ThroughAssociation
        private

        # Builds the preloader scope taking into account a potential
        # +as_of_time+ passed down the call chain starting at the
        # end user invocation.
        # 
        # Also handles WHERE clauses properly in temporal context to avoid
        # referencing tables not available in temporal subqueries.
        #
        def through_scope
          scope = through_reflection.klass.unscoped
          options = reflection.options

          return scope if options[:disable_joins]

          values = reflection_scope.values
          if annotations = values[:annotate]
            scope.annotate!(*annotations)
          end

          if options[:source_type]
            scope.where! reflection.foreign_type => options[:source_type]
          elsif !reflection_scope.where_clause.empty?
            # Check if we're in a temporal context and the target class is chrono
            if preload_scope.try(:as_of_time) && scope.klass.try(:chrono?)
              # Store the where clause to apply after temporal setup
              where_clause = reflection_scope.where_clause
              
              # Apply temporal transformation first
              scope = scope.as_of(preload_scope.as_of_time)
              
              # Re-apply where clause after temporal setup
              scope.where_clause += where_clause unless where_clause.empty?
            else
              # Original behavior for non-temporal context
              scope.where_clause = reflection_scope.where_clause
            end

            if includes = values[:includes]
              scope.includes!(source_reflection.name => includes)
            else
              scope.includes!(source_reflection.name)
            end

            if values[:references] && !values[:references].empty?
              scope.references_values |= values[:references]
            else
              scope.references!(source_reflection.table_name)
            end

            if joins = values[:joins]
              scope.joins!(source_reflection.name => joins)
            end

            if left_outer_joins = values[:left_outer_joins]
              scope.left_outer_joins!(source_reflection.name => left_outer_joins)
            end

            if scope.eager_loading? && order_values = values[:order]
              scope = scope.order(order_values)
            end
          end

          cascade_strict_loading(scope)
        end
      end
    end
  end
end
