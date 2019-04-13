module ChronoTest::Helpers

  module TimeMachine
    def self.included(base)
      base.extend(self)
    end

    def adapter
      ChronoTest.connection
    end

    def with_revert
      adapter.transaction do
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
        obj.singleton_class.instance_eval do
          define_method(:ts) { @_ts ||= [] }
        end unless obj.methods.include?(:ts)

        now = ChronoTest.connection.select_value('select now()::timestamp') + 'Z'
        obj.ts.push(Time.parse(now))
      end
    end
  end

end
