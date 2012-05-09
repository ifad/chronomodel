module ChronoModel
  class Railtie < ::Rails::Railtie
    rake_tasks do

      namespace :db do
        namespace :chrono do
          task :create_schemas do
            ActiveRecord::Base.connection.chrono_create_schemas!
          end
        end
      end

      task 'db:schema:load' => 'db:chrono:create_schemas'
    end

    class SchemaDumper < ::ActiveRecord::SchemaDumper
      def tables(*)
        super
        @connection.send(:_on_temporal_schema) { super }
      end

      def indexes(table, stream)
        super
        if @connection.is_chrono?(table)
          stream.rewind
          t = stream.read.sub(':force => true', '\&, :temporal => true') # HACK
          stream.seek(0)
          stream.truncate(0)
          stream.write(t)
        end
      end

    end

    # I'm getting (too) used to this (dirty) override scheme.
    #
    silence_warnings do
      ::ActiveRecord::SchemaDumper = SchemaDumper
    end
  end
end
