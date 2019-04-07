require 'active_record/connection_adapters/postgresql_adapter'

require 'chrono_model/adapter/migrations'
require 'chrono_model/adapter/ddl'
require 'chrono_model/adapter/indexes'
require 'chrono_model/adapter/tsrange'
require 'chrono_model/adapter/upgrade'

module ChronoModel

  # This class implements all ActiveRecord::ConnectionAdapters::SchemaStatements
  # methods adding support for temporal extensions. It inherits from the Postgres
  # adapter for a clean override of its methods using super.
  #
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    include ChronoModel::Adapter::Migrations
    include ChronoModel::Adapter::DDL
    include ChronoModel::Adapter::Indexes
    include ChronoModel::Adapter::TSRange
    include ChronoModel::Adapter::Upgrade

    # The schema holding current data
    TEMPORAL_SCHEMA = 'temporal'

    # The schema holding historical data
    HISTORY_SCHEMA  = 'history'

    # Returns true whether the connection adapter supports our
    # implementation of temporal tables. Currently, Chronomodel
    # is supported starting with PostgreSQL 9.3.
    #
    def chrono_supported?
      postgresql_version >= 90300
    end

    def chrono_setup!
      chrono_ensure_schemas

      chrono_upgrade_warning
    end

    # Runs primary_key, indexes and default_sequence_name in the
    # temporal schema, as the table there defined is the source for
    # this information.
    #
    # Moreover, the PostgreSQLAdapter +indexes+ method uses
    # current_schema(), thus this is the only (and cleanest) way to
    # make injection work.
    #
    # Schema nesting is disabled on these calls, make sure to fetch
    # metadata from the first caller's selected schema and not from
    # the current one.
    #
    def primary_key(table_name)
    end

    [:primary_key, :indexes, :default_sequence_name].each do |method|
      define_method(method) do |*args|
        table_name = args.first
        return super(*args) unless is_chrono?(table_name)
        on_schema(TEMPORAL_SCHEMA, recurse: :ignore) { super(*args) }
      end
    end

    # Runs column_definitions in the temporal schema, as the table there
    # defined is the source for this information.
    #
    # The default search path is included however, since the table
    # may reference types defined in other schemas, which result in their
    # names becoming schema qualified, which will cause type resolutions to fail.
    #
    define_method(:column_definitions) do |table_name|
      return super(table_name) unless is_chrono?(table_name)
      on_schema(TEMPORAL_SCHEMA + ',' + self.schema_search_path, recurse: :ignore) { super(table_name) }
    end

    # Evaluates the given block in the given +schema+ search path.
    #
    # Recursion works by saving the old_path the function closure
    # at each recursive call.
    #
    def on_schema(schema, recurse: :follow)
      old_path = self.schema_search_path

      count_recursions do
        if recurse == :follow or Thread.current['recursions'] == 1
          self.schema_search_path = schema
        end

        yield
      end

    ensure
      self.schema_search_path = old_path

      # If the transaction is aborted, any execute() call will raise
      # "transaction is aborted errors" - thus calling the Adapter's
      # setter won't update the memoized variable.
      #
      # Here we reset it to +nil+ to refresh it on the next call, as
      # there is no way to know which path will be restored when the
      # transaction ends.
      #
      if @connection.transaction_status == PG::Connection::PQTRANS_INERROR &&
        Thread.current['recursions'] == 1

        @schema_search_path = nil
      end
    end

    # Returns true if the given name references a temporal table.
    #
    def is_chrono?(table)
      on_temporal_schema { data_source_exists?(table) } &&
        on_history_schema { data_source_exists?(table) }

    rescue ActiveRecord::StatementInvalid => e
      # means that we could not change the search path to check for
      # table existence
      if is_exception_class?(e, PG::InvalidSchemaName, PG::InvalidParameterValue)
        return false
      else
        raise e
      end
    end

    def is_exception_class?(e, *klasses)
      if e.respond_to?(:original_exception)
        klasses.any? { |k| e.is_a?(k) }
      else
        klasses.any? { |k| e.message =~ /#{k.name}/ }
      end
    end

    private
      # Counts the number of recursions in a thread local variable
      #
      def count_recursions # yield
        Thread.current['recursions'] ||= 0
        Thread.current['recursions'] += 1

        yield

      ensure
        Thread.current['recursions'] -= 1
      end

      # Create the temporal and history schemas, unless they already exist
      #
      def chrono_ensure_schemas
        [TEMPORAL_SCHEMA, HISTORY_SCHEMA].each do |schema|
          execute "CREATE SCHEMA #{schema}" unless schema_exists?(schema)
        end
      end

      def on_temporal_schema(nesting = true, &block)
        on_schema(TEMPORAL_SCHEMA, nesting, &block)
      end

      def on_history_schema(nesting = true, &block)
        on_schema(HISTORY_SCHEMA, nesting, &block)
      end

      def translate_exception(exception, message)
        if exception.message =~ /conflicting key value violates exclusion constraint/
          ActiveRecord::RecordNotUnique.new(message)
        else
          super
        end
      end
  end

end
