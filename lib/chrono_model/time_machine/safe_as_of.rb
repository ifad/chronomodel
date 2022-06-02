# frozen_string_literal: true

module ChronoModel
  module TimeMachine
    module SafeAsOf
      def safe_as_of(time)
        if time.present?
          as_of(time)
        else
          all
        end
      end
    end
  end
end
