require 'active_record'

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
    class Association < ActiveRecord::Associations::Association

      # If the association class or the through association are ChronoModels,
      # then fetches the records from a virtual table using a subquery scope
      # to a specific timestamp.
      def scope
        scope = super
        return scope unless _chrono_record?

        klass = reflection.options[:polymorphic] ?
          owner.public_send(reflection.foreign_type).constantize :
          reflection.klass

        if klass.chrono?
          # For standard associations, replace the table name with the virtual
          # as-of table name at the owner's as-of-time
          #
          scope = scope.readonly.from(klass.history.virtual_table_at(owner.as_of_time))
        elsif respond_to?(:through_reflection) && through_reflection.klass.chrono?

          # For through associations, replace the joined table name instead.
          #
          scope.join_sources.each do |join|
            if join.left.name == through_reflection.klass.table_name
              v_table = through_reflection.klass.history.virtual_table_at(
                owner.as_of_time, join.left.table_alias || join.left.table_name)

              # avoid problems in Rails when code down the line expects the
              # join.left to respond to the following methods. we modify
              # the instance of SqlLiteral to do just that.
              table_name  = join.left.table_name
              table_alias = join.left.table_alias
              join.left   = Arel::Nodes::SqlLiteral.new(v_table)

              class << join.left
                attr_accessor :name, :table_name, :table_alias
              end

              join.left.name        = table_name
              join.left.table_name  = table_name
              join.left.table_alias = table_alias
            end
          end

        end

        return scope
      end

      private
        def _chrono_record?
          owner.respond_to?(:as_of_time) && owner.as_of_time.present?
        end
    end

  end
end
