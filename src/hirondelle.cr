require "db"
require "pg"

module Hirondelle
  VERSION = "0.1.0"

  macro included
    macro inherited
      \{% unless @type.abstract? %}
        Hirondelle.register self.new
      \{% end %}
    end
  end

  # Stockage des migrations découvertes
  @@migrations = [] of Migration

  def self.migrations
    @@migrations.sort_by(&.version)
  end

  def self.register(migration : Migration)
    @@migrations << migration
  end

  abstract class Migration
    include Hirondelle
    getter version : Int64

    def initialize(@version)
    end

    abstract def up(db : DB::Database)
    abstract def down(db : DB::Database)
  end

  class MigrationRunner
    def initialize(@db : DB::Database)
      ensure_migration_table
    end

    private def ensure_migration_table
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version INT8 PRIMARY KEY,
          executed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      SQL
    end

    def run_pending(migrations : Array(Migration))
      migrations.sort_by(&.version).each do |migration|
        next if migration_exists?(migration.version)
        @db.transaction do |_tx|
          migration.up(@db)
          record_migration(migration.version)
        end
      end
    end

    def rollback
      last_version = @db.query_one? "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1", as: Int64
      return unless last_version

      migration = Hirondelle.migrations.find { |migration_found| migration_found.version == last_version }
      return unless migration

      @db.transaction do |_tx|
        migration.down(@db)
        @db.exec "DELETE FROM schema_migrations WHERE version = $1", last_version
      end
    end

    private def migration_exists?(version : Int64) : Bool
      version_in_db = @db.query_one? "SELECT version FROM schema_migrations WHERE version = $1", version, as: Int64
      version_in_db.is_a? Int64
    end

    private def record_migration(version : Int64)
      @db.exec "INSERT INTO schema_migrations (version) VALUES ($1)", version
    end
  end
end
