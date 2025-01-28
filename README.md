# Hirondelle

A lightweight database migration system for Crystal. Like swallows returning each spring, Hirondelle ensures your migrations are executed reliably and in order.

## Features

- Automatic migration discovery through class inheritance
- Ordered migrations using version numbers
- Transactions support
- Rollback capability
- Clean and simple API
- Framework agnostic
- Support for PostgreSQL

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  hirondelle:
    github: JadeKharats/hirondelle
```

2. Run `shards install`

## Usage

### Create a migration

```crystal
require "hirondelle"

class CreateUsersTable < Hirondelle::Migration
  def initialize
    super(20240128000001_i64)
  end

  def up(db : DB::Database)
    db.exec <<-SQL
      CREATE TABLE users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) NOT NULL UNIQUE,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end

  def down(db : DB::Database)
    db.exec "DROP TABLE users"
  end
end
```

### Run migrations

```crystal
DB.open("postgres://user:pass@localhost:5432/myapp_db") do |db|
  runner = Hirondelle::MigrationRunner.new(db)
  runner.run_pending(Hirondelle.migrations)
end
```

### Rollback last migration

```crystal
runner.rollback
```

## How it works

Hirondelle uses Crystal's macro system to automatically register migrations. When you create a new migration class inheriting from `Hirondelle::Migration`, it's automatically added to the list of available migrations.

Migrations are executed in order based on their version number. The system keeps track of executed migrations in a `schema_migrations` table, ensuring each migration runs only once.

All migrations are executed within a transaction to ensure database consistency.

## Contributing

1. Fork it (<https://github.com/JadeKharats/hirondelle/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
