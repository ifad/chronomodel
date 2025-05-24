# frozen_string_literal: true

require 'support/adapter/shared_contexts'

# This module contains the definition of a test structure that is used by the
# adapter methods tests, that look up in the database directly whether the
# expected objects have been created.
#
# The structure definition below serves as a blueprint of what it can be
# defined, and as a reference of what it is expected to have been created by
# the +ChronoModel::Adapter+ methods.
#
module ChronoTest
  module Adapter
    module Structure
      extend ActiveSupport::Concern

      included do
        delegate :adapter, to: ChronoTest

        subject { table }

        let(:table) { 'test_table' }
        let(:columns) do
          native = [
            ['test', 'character varying'],
            %w[foo integer],
            ['bar', 'double precision'],
            %w[baz text]
          ]

          def native.to_proc
            proc { |t|
              t.string  :test, null: false, default: 'default-value'
              t.integer :foo
              t.float   :bar
              t.text    :baz
              t.integer :ary, array: true, null: false, default: []
              t.boolean :bool, null: false, default: false
            }
          end

          native
        end
      end
    end
  end
end
