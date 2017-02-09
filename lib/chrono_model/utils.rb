module ChronoModel

  module Conversions
    extend self

    ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(?:\.(\d+))?\z/

    def string_to_utc_time(string)
      if string =~ ISO_DATETIME
        Time.utc $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, $7.to_i
      end
    end

    def time_to_utc_string(time)
      [time.to_s(:db), sprintf('%06d', time.usec)].join '.'
    end
  end

  module Json
    extend self

    def create
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

  module Utilities
    # Amends the given history item setting a different period.
    # Useful when migrating from legacy systems.
    #
    def amend_period!(hid, from, to)
      unless [from, to].any? {|ts| ts.respond_to?(:zone) && ts.zone == 'UTC'}
        raise 'Can amend history only with UTC timestamps'
      end

      connection.execute %[
        UPDATE #{quoted_table_name}
           SET "validity" = tsrange(#{connection.quote(from)}, #{connection.quote(to)})
         WHERE "hid" = #{hid.to_i}
      ]
    end

    # Returns true if this model is backed by a temporal table,
    # false otherwise.
    #
    def chrono?
      connection.is_chrono?(table_name)
    end
  end

  ActiveRecord::Base.extend Utilities

  module Migrate
    extend self

    def upgrade_indexes!(base = ActiveRecord::Base)
      use base

      db.on_schema(Adapter::HISTORY_SCHEMA) do
        db.tables.each do |table|
          if db.is_chrono?(table)
            upgrade_indexes_for(table)
          end
        end
      end
    end

    private
      attr_reader :db

      def use(ar)
        @db = ar.connection
      end

      def upgrade_indexes_for(table_name)
        upgradeable =
          %r{_snapshot$|_valid_(?:from|to)$|_recorded_at$|_instance_(?:update|history)$}

        indexes_sql = %[
          SELECT DISTINCT i.relname
          FROM pg_class t
          INNER JOIN pg_index d ON t.oid = d.indrelid
          INNER JOIN pg_class i ON d.indexrelid = i.oid
          WHERE i.relkind = 'i'
          AND d.indisprimary = 'f'
          AND t.relname = '#{table_name}'
          AND i.relnamespace IN (SELECT oid FROM pg_namespace WHERE nspname = ANY(current_schemas(false)) )
        ]

        db.select_values(indexes_sql).each do |idx|
          if idx =~ upgradeable
            db.execute "DROP INDEX #{idx}"
          end
        end

        db.send(:chrono_create_history_indexes_for, table_name)
      end
  end

end
