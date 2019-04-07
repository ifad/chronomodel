module ChronoModel

  module Json
    extend self

    def create
      puts "ChronoModel: WARNING - JSON ops are deprecated. Please migrate to JSONB"

      adapter.execute 'CREATE OR REPLACE LANGUAGE plpythonu'
      adapter.execute File.read(sql 'json_ops.sql')
    end

    def drop
      adapter.execute File.read(sql 'uninstall-json_ops.sql')
      adapter.execute 'DROP LANGUAGE IF EXISTS plpythonu'
    end

    private
    def sql(file)
      File.dirname(__FILE__) + '/../../sql/' + file
    end

    def adapter
      ActiveRecord::Base.connection
    end
  end

end
