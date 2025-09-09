# frozen_string_literal: true

module ChronoModel
  module Patches
    # Patches ActiveRecord::Associations::Preloader to add support for
    # temporal associations. This is tying itself to Rails internals
    # and it is ugly :-(.
    module Preloader
      # @return [Hash] ChronoModel-specific options including as_of_time and model
      attr_reader :chronomodel_options

      # Initializes the preloader with ChronoModel temporal options.
      #
      # Overwrite the initializer to set Chronomodel +as_of_time+ and +model+
      # options.
      #
      # @param options [Hash] preloader options
      # @option options [Time] :as_of_time timestamp for temporal queries
      # @option options [Class] :model the model class for the association
      # @option options [ActiveRecord::Relation, Proc] :scope custom scope for preloading
      def initialize(**options)
        @chronomodel_options = options.extract!(:as_of_time, :model)
        options[:scope] = chronomodel_scope(options[:scope]) if options.key?(:scope)

        super
      end

      private

      # Creates or modifies the preload scope for temporal queries.
      #
      # @param given_preload_scope [ActiveRecord::Relation, Proc, nil] the original scope
      # @return [ActiveRecord::Relation, Proc] the scope with temporal settings applied
      # @api private
      def chronomodel_scope(given_preload_scope)
        preload_scope = given_preload_scope

        if chronomodel_options[:as_of_time]
          preload_scope ||= ChronoModel::Patches::AsOfTimeRelation.new(chronomodel_options[:model])
          preload_scope.as_of_time!(chronomodel_options[:as_of_time])
        end

        preload_scope
      end

      # Patches for individual association preloading.
      module Association
        private

        # Builds the preloader scope taking into account a potential
        # +as_of_time+ passed down the call chain starting at the
        # end user invocation.
        #
        # @return [ActiveRecord::Relation] the association scope with temporal settings
        # @api private
        def build_scope
          scope = super

          if preload_scope.try(:as_of_time)
            scope = scope.as_of(preload_scope.as_of_time)
          end

          scope
        end
      end

      # Patches for through association preloading.
      module ThroughAssociation
        private

        # Builds the preloader scope taking into account a potential
        # +as_of_time+ passed down the call chain starting at the
        # end user invocation.
        #
        # @return [ActiveRecord::Relation] the through association scope with temporal settings
        # @api private
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
