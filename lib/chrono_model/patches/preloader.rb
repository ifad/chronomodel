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
        def through_scope
          scope = super

          if preload_scope.try(:as_of_time)
            # For historical queries, we need to be careful about WHERE clauses that reference
            # tables that won't be available in the historical subquery.
            # 
            # When Rails builds the through_scope for an association like:
            #   has_many :active_sub_bars, -> { where(active: true) }, through: :bars
            # 
            # It creates a scope that includes the WHERE clause "sub_bars.active = TRUE"
            # However, when we apply as_of(), ChronoModel wraps the main table (bars) in a 
            # historical subquery, but the WHERE clause referencing sub_bars gets moved into
            # that subquery where sub_bars is not available.
            #
            # The solution is to remove WHERE clauses that reference tables other than the
            # through table before applying the historical transformation.
            through_table_name = reflection.through_reflection.table_name
            
            if !scope.where_clause.empty?
              # Filter out WHERE predicates that reference tables other than the through table
              # Note: we access via send since predicates is protected in Rails 8.0
              original_predicates = scope.where_clause.send(:predicates)
              valid_predicates = original_predicates.select do |predicate|
                table_references = extract_table_references(predicate)
                table_references.empty? || table_references.all? { |ref| ref == through_table_name }
              end
              
              if valid_predicates.size != original_predicates.size
                # Some predicates were filtered out, rebuild the where clause
                scope = scope.unscope(:where)
                unless valid_predicates.empty?
                  scope = scope.where(valid_predicates.reduce { |combined, predicate| combined.and(predicate) })
                end
              end
            end
            
            scope = scope.as_of(preload_scope.as_of_time)
          end

          scope
        end
        
        private
        
        # Extract table names referenced in an Arel predicate
        def extract_table_references(predicate)
          table_refs = []
          
          case predicate
          when Arel::Nodes::Equality, Arel::Nodes::NotEqual, Arel::Nodes::LessThan, 
               Arel::Nodes::LessThanOrEqual, Arel::Nodes::GreaterThan, Arel::Nodes::GreaterThanOrEqual,
               Arel::Nodes::In, Arel::Nodes::NotIn, Arel::Nodes::Matches, Arel::Nodes::DoesNotMatch
            # Extract table name from left side if it's an attribute
            if predicate.left.respond_to?(:relation) && predicate.left.relation.respond_to?(:name)
              table_refs << predicate.left.relation.name
            end
            # Extract table name from right side if it's an attribute
            if predicate.right.respond_to?(:relation) && predicate.right.relation.respond_to?(:name)
              table_refs << predicate.right.relation.name
            end
          when Arel::Nodes::And, Arel::Nodes::Or
            # Recursively process compound predicates
            table_refs.concat(extract_table_references(predicate.left))
            table_refs.concat(extract_table_references(predicate.right))
          end
          
          table_refs.uniq
        end
      end
    end
  end
end
