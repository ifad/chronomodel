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
        end

        scope.as_of_time!(owner.as_of_time)

        scope
      end

      private

      def _chrono_record?
        owner.class.include?(ChronoModel::Patches::AsOfTimeHolder) && owner.as_of_time.present?
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
