require "db"
require "pg"

# Hirondelle est un module de gestion de migrations de base de données pour Crystal.
# Il permet de définir, enregistrer et exécuter des migrations de manière structurée.
#
# ## Exemple d'utilisation
#
# ```
# class CreateUsersTable < Hirondelle::Migration
#   def initialize
#     super(1) # Version de la migration
#   end
#
#   def up(db : DB::Database)
#     db.exec <<-SQL
#       CREATE TABLE users (
#         id SERIAL PRIMARY KEY,
#         name TEXT NOT NULL
#       )
#     SQL
#   end
#
#   def down(db : DB::Database)
#     db.exec "DROP TABLE users"
#   end
# end
#
# db = DB.open("postgres://user:password@localhost/dbname")
# runner = Hirondelle::MigrationRunner.new(db)
# runner.run_pending(Hirondelle.migrations)
# ```
module Hirondelle
  VERSION = "0.1.0"

  # Enregistre automatiquement les classes de migration héritant de `Hirondelle::Migration`.
  macro included
    macro inherited
      \{% unless @type.abstract? %}
        Hirondelle.register self.new
      \{% end %}
    end
  end

  # Liste des migrations enregistrées.
  @@migrations = [] of Migration

  # Retourne la liste des migrations triées par version.
  #
  # ```
  # Hirondelle.migrations # => [migration1, migration2, ...]
  # ```
  def self.migrations
    @@migrations.sort_by(&.version)
  end

  # Enregistre une nouvelle migration.
  #
  # - `migration` : Une instance de `Hirondelle::Migration`.
  #
  # ```
  # Hirondelle.register(migration)
  # ```
  def self.register(migration : Migration)
    @@migrations << migration
  end

  # Classe abstraite représentant une migration de base de données.
  # Toutes les migrations doivent hériter de cette classe et implémenter les méthodes `up` et `down`.
  #
  # ## Exemple
  #
  # ```
  # class CreateUsersTable < Hirondelle::Migration
  #   def initialize
  #     super(1) # Version de la migration
  #   end
  #
  #   def up(db : DB::Database)
  #     db.exec <<-SQL
  #       CREATE TABLE users (
  #         id SERIAL PRIMARY KEY,
  #         name TEXT NOT NULL
  #       )
  #     SQL
  #   end
  #
  #   def down(db : DB::Database)
  #     db.exec "DROP TABLE users"
  #   end
  # end
  # ```
  abstract class Migration
    include Hirondelle

    # Version de la migration.
    getter version : Int64

    # Initialise une migration avec une version donnée.
    #
    # - `version` : La version de la migration (doit être unique).
    def initialize(@version)
    end

    # Applique la migration.
    #
    # - `db` : La connexion à la base de données.
    abstract def up(db : DB::Database)

    # Annule la migration.
    #
    # - `db` : La connexion à la base de données.
    abstract def down(db : DB::Database)
  end

  # Classe responsable de l'exécution et de l'annulation des migrations.
  #
  # ## Exemple
  #
  # ```
  # db = DB.open("postgres://user:password@localhost/dbname")
  # runner = Hirondelle::MigrationRunner.new(db)
  # runner.run_pending(Hirondelle.migrations)
  # runner.rollback
  # ```
  class MigrationRunner
    # Initialise un nouveau `MigrationRunner` avec une connexion à la base de données.
    #
    # - `db` : La connexion à la base de données.
    def initialize(@db : DB::Database)
      ensure_migration_table
    end

    # Crée la table `schema_migrations` si elle n'existe pas déjà.
    private def ensure_migration_table
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version INT8 PRIMARY KEY,
          executed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      SQL
    end

    # Applique les migrations en attente.
    #
    # - `migrations` : La liste des migrations à appliquer.
    def run_pending(migrations : Array(Migration))
      migrations.sort_by(&.version).each do |migration|
        next if migration_exists?(migration.version)
        @db.transaction do |_tx|
          migration.up(@db)
          record_migration(migration.version)
        end
      end
    end

    # Annule la dernière migration appliquée.
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

    # Vérifie si une migration a déjà été appliquée.
    #
    # - `version` : La version de la migration à vérifier.
    # - Retourne `true` si la migration existe, sinon `false`.
    private def migration_exists?(version : Int64) : Bool
      version_in_db = @db.query_one? "SELECT version FROM schema_migrations WHERE version = $1", version, as: Int64
      version_in_db.is_a? Int64
    end

    # Enregistre une migration dans la table `schema_migrations`.
    #
    # - `version` : La version de la migration à enregistrer.
    private def record_migration(version : Int64)
      @db.exec "INSERT INTO schema_migrations (version) VALUES ($1)", version
    end
  end
end
