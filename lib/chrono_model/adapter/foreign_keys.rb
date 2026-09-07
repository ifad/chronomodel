# frozen_string_literal: true

module ChronoModel
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    # Overrides foreign key schema statements to support temporal tables.
    #
    # A temporal table is backed by a read/write view in the default schema,
    # while the actual table lives in the temporal schema. As PostgreSQL
    # cannot add constraints to views, foreign keys on temporal tables are
    # created on the table in the temporal schema.
    #
    # See https://github.com/ifad/chronomodel/issues/174.
    #
    module ForeignKeys
      # Adds a foreign key between two tables.
      #
      # When either table is temporal, the foreign key is created on (or
      # referencing) the table in the temporal schema: the search path is
      # set to the temporal schema first, falling back to the current one,
      # so that plain tables keep resolving to their own schema. This
      # supports all combinations of temporal and plain tables on both
      # sides of the foreign key.
      #
      # The history table never carries foreign keys: PostgreSQL does not
      # propagate them to inheritance children, thus historical records
      # keep referencing data that may have been deleted later on.
      #
      def add_foreign_key(from_table, to_table, **options)
        return super unless is_chrono?(from_table) || is_chrono?(to_table)

        on_temporal_schema_with_fallback do
          super(chrono_unqualify(from_table), chrono_unqualify(to_table), **options)
        end
      end

      # Removes a foreign key, applying the same schema redirection as
      # +add_foreign_key+. The internal lookup of the constraint name
      # through +foreign_keys+ has to happen in the temporal schema as
      # well, given the constraint is defined there.
      #
      def remove_foreign_key(from_table, to_table = nil, **options)
        # NOTE: +to_table+ can be passed as a keyword argument, e.g. by
        # +remove_reference+, which forwards the :foreign_key option hash.
        #
        referenced_table = to_table || options[:to_table]

        return super unless is_chrono?(from_table) || (referenced_table && is_chrono?(referenced_table))

        to_table = chrono_unqualify(to_table) if to_table
        options[:to_table] = chrono_unqualify(options[:to_table]) if options[:to_table]

        on_temporal_schema_with_fallback do
          super(chrono_unqualify(from_table), to_table, **options)
        end
      end

      # Reads the foreign keys of a temporal table from the table in the
      # temporal schema, where they are defined. Used by Rails' schema
      # statements (e.g. +foreign_key_exists?+) and by schema dumpers.
      #
      def foreign_keys(table_name)
        return super unless is_chrono?(table_name)

        on_temporal_schema_with_fallback { super(chrono_unqualify(table_name)) }
      end

      # Checks foreign key existence applying the same schema redirection
      # as +add_foreign_key+, so that checks against temporal tables match
      # the constraints defined in the temporal schema.
      #
      def foreign_key_exists?(from_table, to_table = nil, **options)
        referenced_table = to_table || options[:to_table]

        return super unless is_chrono?(from_table) || (referenced_table && is_chrono?(referenced_table))

        to_table = chrono_unqualify(to_table) if to_table
        options[:to_table] = chrono_unqualify(options[:to_table]) if options[:to_table]

        on_temporal_schema_with_fallback do
          super(chrono_unqualify(from_table), to_table, **options)
        end
      end

      private

      # Evaluates the given block with the search path set to the temporal
      # schema, falling back to the current search path - which usually
      # holds the default schema - for plain tables.
      #
      # Recursion is ignored so that calls made while already scoped to a
      # schema (e.g. from +change_table+) resolve tables using the schema
      # selected by the first caller, as done by +column_definitions+.
      #
      def on_temporal_schema_with_fallback(&block)
        on_schema("#{TEMPORAL_SCHEMA},#{schema_search_path}", recurse: :ignore, &block)
      end

      # Strips the temporal schema qualification from the given table name:
      # under the redirected search path, "temporal.table" and "table" refer
      # to the same table, but constraint metadata is rendered and looked up
      # through the unqualified name.
      #
      def chrono_unqualify(table_name)
        table_name.to_s.delete_prefix("#{TEMPORAL_SCHEMA}.")
      end
    end
  end
end
