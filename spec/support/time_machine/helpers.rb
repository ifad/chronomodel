module ChronoTest
  module TimeMachine
    # This module contains helpers used throughout the
    # +ChronoModel::TimeMachine+ specs.
    #
    module Helpers
      def self.included(base)
        base.extend(self)
      end

      def adapter
        ChronoTest.connection
      end

      def with_revert
        adapter.transaction do
          adapter.materialize_transactions if adapter.respond_to?(:materialize_transactions)
          adapter.create_savepoint 'revert'

          yield

          adapter.exec_rollback_to_savepoint 'revert'
        end
      end

      # If a context object is given, evaluates the given
      # block in its instance context, then defines a `ts`
      # on it, backed by an Array, and adds the current
      # database timestamp to it.
      #
      # If a context object is not given, the block is
      # evaluated in the current context and the above
      # mangling is done on the blocks' return value.
      #
      def ts_eval(ctx = nil, &block)
        ret = (ctx || self).instance_eval(&block)
        (ctx || ret).tap do |obj|
          unless obj.methods.include?(:ts)
            obj.singleton_class.instance_eval do
              define_method(:ts) { @ts ||= [] }
            end
          end

          now = ChronoTest.connection.select_value('select now()::timestamp')
          case now
          when Time # Already parsed, thanks AR
            obj.ts.push(now)
          when String # ISO8601 Timestamp
            obj.ts.push(Time.parse("#{now}Z"))
          else
            raise "Don't know how to deal with #{now.inspect}"
          end
        end
      end
    end
  end
end
