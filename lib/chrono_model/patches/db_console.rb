module ChronoModel
  module Patches

    module DBConsole
      def config
        super.dup.tap {|config| config['adapter'] = 'postgresql/chronomodel' }
      end
    end

  end
end
