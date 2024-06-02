# frozen_string_literal: true

module ChronoModel
  module Patches
    # Patches ActiveRecord::Associations::Preloader to add support for
    # temporal associations. This is tying itself to Rails internals
    # and it is ugly :-(.
    #
    module Preloader
      attr_reader :chronomodel_options

      # We overwrite the initializer in order to pass the +as_of_time+
      # parameter above in the build_preloader
      #
      def initialize(**options)
        @chronomodel_options = options.extract!(:as_of_time, :model)
        options[:scope] = chronomodel_scope(options[:scope]) if options.key?(:scope)

        if options.empty?
          super()
        else
          super
        end
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
        # Builds the preloader scope taking into account a potential
        # +as_of_time+ passed down the call chain starting at the
        # end user invocation.
        #
        def through_scope
          scope = super

          if preload_scope.try(:as_of_time)
            scope = scope.as_of(preload_scope.as_of_time)
          end

          scope
        end
      end
    end
  end
end
