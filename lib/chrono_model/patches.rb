require 'active_record'

module ChronoModel
  module Patches

    module AsOfTimeHolder
      # Sets the virtual 'as_of_time' attribute to the given time, converting to UTC.
      #
      # See ChronoModel::Patches::AsOfTimeHolder
      #
      def as_of_time!(time)
        @_as_of_time = time.utc

        self
      end

      # Reads the virtual 'as_of_time' attribute
      #
      # See ChronoModel::Patches::AsOfTimeHolder
      #
      def as_of_time
        @_as_of_time
      end
    end

    module Relation
      include AsOfTimeHolder

      def load
        return super unless @_as_of_time && !loaded?

        super.each {|record| record.as_of_time!(@_as_of_time) }
      end

      def merge(*)
        return super unless @_as_of_time

        super.as_of_time!(@_as_of_time)
      end

      def build_arel
        return super unless @_as_of_time

        super.tap do |arel|

          arel.join_sources.each do |join|
            model = TimeMachine.chrono_models[join.left.table_name]
            next unless model

            join.left = Arel::Nodes::SqlLiteral.new(
              model.history.virtual_table_at(@_as_of_time,
                join.left.table_alias || join.left.table_name)
            )
          end

        end
      end

      def build_preloader
        ActiveRecord::Associations::Preloader.new(as_of_time: as_of_time)
      end
    end

    # Patches ActiveRecord::Associations::Preloader to add support for
    # temporal associations. This is tying itself to Rails internals
    # and it is ugly :-(.
    #
    module Preloader
      attr_reader :options

      NULL_RELATION = ActiveRecord::Associations::Preloader::NULL_RELATION
      AS_OF_PRELOAD_SCOPE = Struct.new(:as_of_time, *NULL_RELATION.members)

      def initialize(options = {})
        @options = options.freeze
      end

      def preload(records, associations, given_preload_scope = nil)
        if (as_of_time = options[:as_of_time])
          preload_scope = AS_OF_PRELOAD_SCOPE.new

          preload_scope.as_of_time = as_of_time
          given_preload_scope ||= NULL_RELATION

          NULL_RELATION.members.each do |member|
            preload_scope[member] = given_preload_scope[member]
          end
        end

        super records, associations, preload_scope
      end

      module Association
        def build_scope
          scope = super

          if preload_scope.respond_to?(:as_of_time)
            scope = scope.as_of(preload_scope.as_of_time)
          end

          return scope
        end
      end
    end

    # Patches ActiveRecord::Associations::Association to add support for
    # temporal associations.
    #
    # Each record fetched from the +as_of+ scope on the owner class will have
    # an additional "as_of_time" field yielding the UTC time of the request,
    # then the as_of scope is called on either this association's class or
    # on the join model's (:through association) one.
    #
    module Association
      def skip_statement_cache?
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

        scope.as_of_time!(owner.as_of_time)

        return scope
      end

      private
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
