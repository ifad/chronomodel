module ChronoModel
  module Patches
    # This class is a dummy relation whose scope is only to pass around the
    # as_of_time parameters across ActiveRecord call chains.
    #
    # With AR 5.2 a simple relation can be used, as the only required argument
    # is the model. 5.0 and 5.1 require more arguments, that are passed here.
    #
    class AsOfTimeRelation < ActiveRecord::Relation
      if ActiveRecord::VERSION::STRING.to_f < 5.2
        def initialize(klass, table: klass.arel_table, predicate_builder: klass.predicate_builder, values: {})
          super(klass, table, predicate_builder, values)
        end
      end
    end
  end
end
