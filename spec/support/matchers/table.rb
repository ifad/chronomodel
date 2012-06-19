module ChronoTest::Matchers

  module Table
    class Base
      attr_reader :table

      def matches?(table)
        table = table.table_name if table.respond_to?(:table_name)
        @table = table
      end
      private :matches? # This is an abstract class

      def failure_message_for_should_not
        failure_message_for_should.gsub(/to /, 'to not ')
      end

      protected
        def table_exists?(options)
          connection.table_exists? [options[:in], table].join('.')
        end

        def connection
          ChronoTest.connection
        end

        def temporal_schema
          ChronoModel::Adapter::TEMPORAL_SCHEMA
        end

        def history_schema
          ChronoModel::Adapter::HISTORY_SCHEMA
        end

        def public_schema
          'public'
        end
    end

    # ##################################################################
    # Checks that a table exists in the Public schema
    #
    class HavePublicBacking < Base
      def matches?(table)
        super(table)

        table_exists? :in => public_schema
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

        table_exists? :in => temporal_schema
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
          @existance = super :in => history_schema
        end

        def inherits_from_temporal?
          @inheritance = connection.select_value(%[ SELECT EXISTS (
            SELECT 1 FROM pg_catalog.pg_inherits
             WHERE inhrelid  = '#{history_schema}.#{table}'::regclass::oid
               AND inhparent = '#{temporal_schema}.#{table}'::regclass::oid
          ) ]) == 't'
        end
    end

    def have_history_backing
      HaveHistoryBacking.new
    end


    # ##################################################################
    # Checks that a table exists in the Public schema, is an updatable
    # view and has an INSERT, UPDATE and DELETE rule.
    #
    class HavePublicInterface < Base
      def matches?(table)
        super(table)

        table_exists? && [ is_updatable?, has_rules? ].all?
      end

      def failure_message_for_should
        "expected #{table} ".tap do |message|
          message << [
            ("to exist in the #{public_schema} schema" unless @existance  ),
            ('to be an updatable view'                 unless @updatable  ),
            ('to have an INSERT rule'                  unless @insert_rule),
            ('to have an UPDATE rule'                  unless @update_rule),
            ('to have a DELETE rule'                   unless @delete_rule)
          ].compact.to_sentence
        end
      end

      private
        def table_exists?
          @existance = super :in => public_schema
        end

        def is_updatable?
          @updatable = connection.select_value(%[
            SELECT is_updatable FROM information_schema.views
             WHERE table_schema = '#{public_schema}'
               AND table_name   = '#{table}'
          ]) == 'YES'
        end

        def has_rules?
          rules = connection.select_values %[
            SELECT UNNEST(REGEXP_MATCHES(
                definition, 'ON (INSERT|UPDATE|DELETE) TO #{table} DO INSTEAD'
              ))
             FROM pg_catalog.pg_rules
            WHERE tablename = '#{table}'
          ]

          @insert_rule = rules.include? 'INSERT'
          @update_rule = rules.include? 'UPDATE'
          @delete_rule = rules.include? 'DELETE'

          @insert_rule && @update_rule && @delete_rule
        end
    end

    def have_public_interface
      HavePublicInterface.new
    end
  end

end
