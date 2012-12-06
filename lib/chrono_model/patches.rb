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
      # then fetches the records from a virtual table using a subquery scoped
      # to a specific timestamp.
      def scoped
        scoped = super
        return scoped unless _chrono_record?

        klass = reflection.options[:polymorphic] ?
          owner.public_send(reflection.foreign_type).constantize :
          reflection.klass

        history = if klass.chrono?
          klass.history
        elsif respond_to?(:through_reflection) && through_reflection.klass.chrono?
          through_reflection.klass.history
        end

        if history
          scoped = scoped.readonly.from(history.virtual_table_at(owner.as_of_time))
        end

        return scoped
      end

      private
        def _chrono_record?
          owner.respond_to?(:as_of_time) && owner.as_of_time.present?
        end
    end

  end
end
