# frozen_string_literal: true

require "lint_roller"

module RuboCop
  module Packaging
    # A plugin that integrates RuboCop Packaging with RuboCop's plugin system.
    class Plugin < LintRoller::Plugin
      def about
        LintRoller::About.new(
          name: "rubocop-packaging",
          version: VERSION,
          homepage: "https://github.com/utkarsh2102/rubocop-packaging",
          description: "A collection of RuboCop cops to check for downstream compatibility issues in the Ruby code."
        )
      end

      def supported?(context)
        context.engine == :rubocop
      end

      def rules(_context)
        LintRoller::Rules.new(
          type: :path,
          config_format: :rubocop,
          value: Pathname.new(__dir__).join("../../../config/default.yml")
        )
      end
    end
  end
end
