module MultiJson
  module Options
    def load_options=(options)
      OptionsCache.reset
      @load_options = options
    end

    def dump_options=(options)
      OptionsCache.reset
      @dump_options = options
    end

    def load_options(*)
      (defined?(@load_options) && get_options(@load_options, *)) || default_load_options
    end

    def dump_options(*)
      (defined?(@dump_options) && get_options(@dump_options, *)) || default_dump_options
    end

    def default_load_options
      @default_load_options ||= {}.freeze
    end

    def default_dump_options
      @default_dump_options ||= {}.freeze
    end

    private

    def get_options(options, *)
      return handle_callable_options(options, *) if options_callable?(options)

      handle_hashable_options(options)
    end

    def options_callable?(options)
      options.respond_to?(:call)
    end

    def handle_callable_options(options, *)
      options.arity.zero? ? options.call : options.call(*)
    end

    def handle_hashable_options(options)
      options.respond_to?(:to_hash) ? options.to_hash : nil
    end
  end
end
