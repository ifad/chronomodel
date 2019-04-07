module ChronoModel
  module Patches

    # Patches ActiveRecord::Associations::Association to add support for
    # temporal associations.
    #
    # Each record fetched from the +as_of+ scope on the owner class will have
    # an additional "as_of_time" field yielding the UTC time of the request,
    # then the as_of scope is called on either this association's class or
    # on the join model's (:through association) one.
    #
    module Association
      def skip_statement_cache?(*)
        super || _chrono_target?
      end

      # If the association class or the through association are ChronoModels,
      # then fetches the records from a virtual table using a subquery scope
      # to a specific timestamp.
      def scope
        scope = super
        return scope unless _chrono_record?

        if _chrono_target?
          # For standard associations, replace the table name with the virtual
          # as-of table name at the owner's as-of-time
          #
          scope = scope.from(klass.history.virtual_table_at(owner.as_of_time))

        elsif respond_to?(:through_reflection) && through_reflection.klass.chrono?

          _chrono_scope_has_many_through_joins(scope)
        end

        scope.as_of_time!(owner.as_of_time)

        return scope
      end

      private
        # For through associations, replace the joined table name with a
        # virtual table that selects records from the history at the given
        # +as_of_time+.
        #
        def _chrono_scope_has_many_through_joins(scope)
          scope.join_sources.each do |join|
            if join.left.name == through_reflection.klass.table_name
              history_model = through_reflection.klass.history

              join.left = ChronoModel::Patches::JoinNode.new(
                join.left, history_model, owner.as_of_time)
            end
          end
        end

        def _chrono_record?
          owner.respond_to?(:as_of_time) && owner.as_of_time.present?
        end

        def _chrono_target?
          @_target_klass ||= reflection.options[:polymorphic] ?
            owner.public_send(reflection.foreign_type).constantize :
            reflection.klass

          @_target_klass.chrono?
        end

    end

  end
end
