# frozen_string_literal: true

module ChronoModel
  class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    module Upgrade
      def chrono_upgrade!
        chrono_ensure_schemas

        chrono_upgrade_structure!
      end

      private

      # Locate tables needing a structure upgrade
      #
      def chrono_tables_needing_upgrade
        tables = {}

        on_temporal_schema { self.tables }.each do |table_name|
          next unless is_chrono?(table_name)

          metadata = chrono_metadata_for(table_name)
          version = metadata['chronomodel']

          if version.blank?
            tables[table_name] = { version: nil, priority: 'CRITICAL' }
          elsif version != VERSION
            tables[table_name] = { version: version, priority: 'LOW' }
          end
        end

        tables
      end

      # Emit a warning about tables needing an upgrade
      #
      def chrono_upgrade_warning
        upgrade = chrono_tables_needing_upgrade.map do |table, desc|
          "#{table} - priority: #{desc[:priority]}"
        end.join('; ')

        return if upgrade.empty?

        logger.warn 'ChronoModel: There are tables needing a structure upgrade, and ChronoModel structures need to be recreated.'
        logger.warn 'ChronoModel: Please run ChronoModel.upgrade! to attempt the upgrade. If you have dependant database objects'
        logger.warn 'ChronoModel: the upgrade will fail and you have to drop the dependent objects, run .upgrade! and create them'
        logger.warn 'ChronoModel: again. Sorry. Some features or the whole library may not work correctly until upgrade is complete.'
        logger.warn "ChronoModel: Tables pending upgrade: #{upgrade}"
      end

      # Upgrades existing structure for each table, if required.
      #
      def chrono_upgrade_structure!
        transaction do
          chrono_tables_needing_upgrade.each do |table_name, desc|
            if desc[:version].blank?
              logger.info "ChronoModel: Upgrading legacy PG 9.0 table #{table_name} to #{VERSION}"
              chrono_upgrade_from_postgres_9_0(table_name)
              logger.info "ChronoModel: legacy #{table_name} upgrade complete"
            else
              logger.info "ChronoModel: upgrading #{table_name} from #{desc[:version]} to #{VERSION}"
              chrono_public_view_ddl(table_name)
              logger.info "ChronoModel: #{table_name} upgrade complete"
            end
          end
        end
      rescue StandardError => e
        message = "ChronoModel structure upgrade failed: #{e.message}. Please drop dependent objects first and then run ChronoModel.upgrade! again."

        # Quite important, output it also to stderr.
        #
        logger.error message
        $stderr.puts message
      end

      def chrono_upgrade_from_postgres_9_0(table_name)
        # roses are red
        # violets are blue
        # and this is the most boring piece of code ever
        history_table = "#{HISTORY_SCHEMA}.#{table_name}"
        p_pkey = primary_key(table_name)

        execute "ALTER TABLE #{history_table} ADD COLUMN validity tsrange;"
        execute <<-SQL
            UPDATE #{history_table} SET validity = tsrange(valid_from,
                CASE WHEN extract(year from valid_to) = 9999 THEN NULL
                     ELSE valid_to
                END
            );
        SQL

        execute "DROP INDEX #{history_table}_temporal_on_valid_from;"
        execute "DROP INDEX #{history_table}_temporal_on_valid_from_and_valid_to;"
        execute "DROP INDEX #{history_table}_temporal_on_valid_to;"
        execute "DROP INDEX #{history_table}_inherit_pkey"
        execute "DROP INDEX #{history_table}_recorded_at"
        execute "DROP INDEX #{history_table}_instance_history"
        execute "ALTER TABLE #{history_table} DROP CONSTRAINT #{table_name}_valid_from_before_valid_to;"
        execute "ALTER TABLE #{history_table} DROP CONSTRAINT #{table_name}_timeline_consistency;"
        execute "DROP RULE #{table_name}_upd_first ON #{table_name};"
        execute "DROP RULE #{table_name}_upd_next ON #{table_name};"
        execute "DROP RULE #{table_name}_del ON #{table_name};"
        execute "DROP RULE #{table_name}_ins ON #{table_name};"
        execute "DROP TRIGGER history_ins ON #{TEMPORAL_SCHEMA}.#{table_name};"
        execute "DROP FUNCTION #{TEMPORAL_SCHEMA}.#{table_name}_ins();"
        execute "ALTER TABLE #{history_table} DROP COLUMN valid_from;"
        execute "ALTER TABLE #{history_table} DROP COLUMN valid_to;"

        execute 'CREATE EXTENSION IF NOT EXISTS btree_gist;'

        chrono_public_view_ddl(table_name)
        on_history_schema { add_history_validity_constraint(table_name, p_pkey) }
        on_history_schema { chrono_create_history_indexes_for(table_name, p_pkey) }
      end
      # private
    end
  end
end
