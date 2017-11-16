module ChronoModel
  module Patches

    module DBConsole
      def config
        super.tap {|config| config['adapter'] = 'postgresql/chronomodel' }
      end
    end

  end
end
