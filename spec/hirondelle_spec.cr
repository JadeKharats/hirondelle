require "./spec_helper"

private class TestMigration1 < Hirondelle::Migration
  def initialize
    super(20240128000001_i64)
  end

  def up(db : DB::Database)
    db.exec <<-SQL
      CREATE TABLE test_table1 (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL
      )
    SQL
  end

  def down(db : DB::Database)
    db.exec "DROP TABLE test_table1"
  end
end

private class TestMigration2 < Hirondelle::Migration
  def initialize
    super(20240128000002_i64)
  end

  def up(db : DB::Database)
    db.exec <<-SQL
      CREATE TABLE test_table2 (
        id SERIAL PRIMARY KEY,
        description TEXT
      )
    SQL
  end

  def down(db : DB::Database)
    db.exec "DROP TABLE test_table2"
  end
end

describe Hirondelle do
  describe "::VERSION" do
    it "is set" do
      Hirondelle::VERSION.should eq "0.1.0"
    end
  end

  describe ".migrations" do
    it "retourne les migrations dans l'ordre" do
      migrations = Hirondelle.migrations
      migrations.size.should eq(2)
      migrations.map(&.version).should eq([20240128000001_i64, 20240128000002_i64])
    end
  end

  describe Hirondelle::Migration do
    it "s'auto-enregistre lors de l'héritage" do
      Hirondelle.migrations.any?(TestMigration1).should be_true
      Hirondelle.migrations.any?(TestMigration2).should be_true
    end
  end

  describe Hirondelle::MigrationRunner do
    db = DB.open(ENV["DATABASE_URL"]? || "postgres://hirondelle_user:hirondelle_password@localhost:5432/hirondelle_db")
    runner = Hirondelle::MigrationRunner.new(db)

    before_each do
      # Nettoie la base de test
      db.exec "DROP TABLE IF EXISTS schema_migrations"
      db.exec "DROP TABLE IF EXISTS test_table1"
      db.exec "DROP TABLE IF EXISTS test_table2"
    end

    after_all do
      db.close
    end

    describe "#run_pending" do
      it "crée la table schema_migrations" do
        runner = Hirondelle::MigrationRunner.new(db)
        db.query_one?("SELECT to_regclass('schema_migrations')", as: String).should_not be_nil
      end

      it "exécute les migrations pendantes" do
        runner = Hirondelle::MigrationRunner.new(db)
        runner.run_pending(Hirondelle.migrations)

        # Vérifie que les tables ont été créées
        db.query_one? "SELECT to_regclass('test_table1')", as: String?.should_not be_nil
        db.query_one? "SELECT to_regclass('test_table2')", as: String?.should_not be_nil
      end

      it "n'exécute pas les migrations déjà appliquées" do
        runner = Hirondelle::MigrationRunner.new(db)
        # Simule une migration déjà exécutée
        db.exec "INSERT INTO schema_migrations (version) VALUES ($1)", 20240128000001_i64

        runner.run_pending(Hirondelle.migrations)

        # Vérifie que seule test_table2 a été créée
        db.query_one?("SELECT to_regclass('test_table1')", as: String?).should be_nil
        db.query_one?("SELECT to_regclass('test_table2')", as: String?).should_not be_nil
      end

      it "enregistre les migrations exécutées" do
        runner = Hirondelle::MigrationRunner.new(db)
        runner.run_pending(Hirondelle.migrations)

        versions = [] of Int64
        db.query "SELECT version FROM schema_migrations ORDER BY version" do |resultset|
          resultset.each do
            versions << resultset.read(Int64)
          end
        end

        versions.should eq([20240128000001_i64, 20240128000002_i64])
      end
    end

    describe "#rollback" do
      it "exécute le down de la dernière migration" do
        runner = Hirondelle::MigrationRunner.new(db)

        runner.run_pending(Hirondelle.migrations)

        db.query_one? "SELECT to_regclass('test_table1')", as: String?.should_not be_nil
        db.query_one? "SELECT to_regclass('test_table2')", as: String?.should_not be_nil

        runner.rollback

        db.query_one? "SELECT to_regclass('test_table1')", as: String?.should_not be_nil
        db.query_one?("SELECT to_regclass('test_table2')", as: String?).should be_nil

        versions = [] of Int64
        db.query "SELECT version FROM schema_migrations ORDER BY version" do |resultset|
          resultset.each do
            versions << resultset.read(Int64)
          end
        end
        versions.should eq([20240128000001_i64])
      end

      it "ne fait rien s'il n'y a pas de migration à rollback" do
        runner = Hirondelle::MigrationRunner.new(db)
        runner.rollback
      end
    end
  end
end
