require 'support/matchers/base'

module ChronoTest::Matchers

  module Table
    class Base < ChronoTest::Matchers::Base

      protected
        # Database statements
        #
        def relation_exists?(options)
          schema = options[:in]
          kind   = options[:kind] == :view ? 'v' : 'r'

          select_value(<<-SQL, [ table, schema ], 'Check table exists') == 't'
            SELECT EXISTS (
              SELECT 1
                FROM pg_class c
                LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE c.relkind = '#{kind}'
                 AND c.relname = $1
                 AND n.nspname = $2
            )
          SQL
        end
    end

    # ##################################################################
    # Checks that a table exists in the Public schema
    #
    class HavePublicBacking < Base
      def matches?(table)
        super(table)

        relation_exists? :in => public_schema
      end

      def description
        'be in the public schema'
      end

      def failure_message_for_should
        "expected #{table} to exist in the #{public_schema} schema"
      end
    end

    def have_public_backing
      HavePublicBacking.new
    end


    # ##################################################################
    # Checks that a table exists in the Temporal schema
    #
    class HaveTemporalBacking < Base
      def matches?(table)
        super(table)

        relation_exists? :in => temporal_schema
      end

      def description
        'be in the temporal schema'
      end

      def failure_message_for_should
        "expected #{table} to exist in the #{temporal_schema} schema"
      end
    end

    def have_temporal_backing
      HaveTemporalBacking.new
    end


    # ##################################################################
    # Checks that a table exists in the History schema and inherits from
    # the one in the Temporal schema
    #
    class HaveHistoryBacking < Base
      def matches?(table)
        super(table)

        table_exists? && inherits_from_temporal?
      end

      def description
        'be in history schema'
      end

      def failure_message_for_should
        "expected #{table} ".tap do |message|
          message << [
            ("to exist in the #{history_schema} schema"    unless @existance),
            ("to inherit from #{temporal_schema}.#{table}" unless @inheritance)
          ].compact.to_sentence
        end
      end

      private
        def table_exists?
          @existance = relation_exists? :in => history_schema
        end

        def inherits_from_temporal?
          binds = ["#{history_schema}.#{table}", "#{temporal_schema}.#{table}"]

          @inheritance = select_value(<<-SQL, binds, 'Check inheritance') == 't'
            SELECT EXISTS (
              SELECT 1 FROM pg_catalog.pg_inherits
               WHERE inhrelid  = $1::regclass::oid
                 AND inhparent = $2::regclass::oid
            )
          SQL
        end
    end

    def have_history_backing
      HaveHistoryBacking.new
    end


    # ##################################################################
    # Checks that a table exists in the Public schema, is an updatable
    # view and has an INSERT, UPDATE and DELETE triggers.
    #
    class HavePublicInterface < Base
      def matches?(table)
        super(table)

        view_exists? && [ is_updatable?, has_triggers? ].all?
      end

      def description
        'be an updatable view'
      end

      def failure_message_for_should
        "expected #{table} ".tap do |message|
          message << [
            ("to exist in the #{public_schema} schema" unless @existance     ),
            ('to be an updatable view'                 unless @updatable     ),
            ('to have an INSERT trigger'               unless @insert_trigger),
            ('to have an UPDATE trigger'               unless @update_trigger),
            ('to have a DELETE trigger'                unless @delete_trigger)
          ].compact.to_sentence
        end
      end

      private
        def view_exists?
          @existance = relation_exists? :in => public_schema, :kind => :view
        end

        def is_updatable?
          binds = [ public_schema, table ]

          @updatable = select_value(<<-SQL, binds, 'Check updatable') == 'YES'
            SELECT is_updatable FROM information_schema.views
             WHERE table_schema = $1 AND table_name = $2
          SQL
        end

        def has_triggers?
          triggers = select_values(<<-SQL, [ public_schema, table ], 'Check triggers')
            SELECT t.tgname
              FROM pg_catalog.pg_trigger t, pg_catalog.pg_class c, pg_catalog.pg_namespace n
             WHERE t.tgrelid = c.relfilenode
               AND n.oid = c.relnamespace
               AND n.nspname = $1
               AND c.relname = $2;
          SQL

          @insert_trigger = triggers.include? 'chronomodel_insert'
          @update_trigger = triggers.include? 'chronomodel_update'
          @delete_trigger = triggers.include? 'chronomodel_delete'

          @insert_trigger && @update_trigger && @delete_trigger
        end
    end

    def have_public_interface
      HavePublicInterface.new
    end
  end

end
