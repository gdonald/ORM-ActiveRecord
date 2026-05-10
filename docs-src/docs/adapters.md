# Adapters

ORM::ActiveRecord supports three database backends out of the box: PostgreSQL,
MySQL, and SQLite. Tests run against all three on every CI build, and the
adapter API is designed so application code is the same regardless of the
backend.

## Selecting an adapter

Two mechanisms drive adapter selection. They're checked in this order:

1. **`DATABASE_URL` environment variable** (preferred)
2. **`config/application.json`** (fallback)

### DATABASE_URL

```shell
DATABASE_URL=postgres://user:pass@host:5432/dbname?schema=public
DATABASE_URL=mysql://root:secret@127.0.0.1:3306/dbname
DATABASE_URL=sqlite:db/test.sqlite3
DATABASE_URL=sqlite::memory:
```

Recognised schemes:

| Scheme(s)                       | Adapter      |
| ------------------------------- | ------------ |
| `pg`, `postgres`, `postgresql`  | PostgreSQL   |
| `mysql`, `mysql2`, `mariadb`    | MySQL        |
| `sqlite`, `sqlite3`             | SQLite       |

Query-string parameters are passed through as adapter options (`?schema=public`,
`?sslmode=require`, etc.).

### config/application.json

If `DATABASE_URL` is unset, ORM::ActiveRecord reads `config/application.json`.
Three example templates live in `config/`:

```shell
cp config/application.json-pg-example     config/application.json
cp config/application.json-mysql-example  config/application.json
cp config/application.json-sqlite-example config/application.json
```

The shape:

```json
{
  "db": {
    "adapter": "pg",
    "host": "localhost",
    "port": 5432,
    "name": "ar_test",
    "user": "postgres",
    "password": "",
    "schema": "public"
  }
}
```

`adapter` must be one of `pg` / `mysql` / `sqlite` (the same aliases as
`DATABASE_URL` schemes are accepted). MySQL has no separate schema concept —
the `name` field IS the schema. SQLite only needs `name` (the file path) or
`":memory:"`.

## Adapter-specific notes

### PostgreSQL

The default adapter. Uses `$N` bind placeholders and emits
`INSERT … RETURNING id` for surrogate-key reads. Schema introspection goes
through `information_schema`. Boolean and timestamp values round-trip directly.

### MySQL

Uses `?` bind placeholders and `LAST_INSERT_ID()` for surrogate-key reads
(MySQL has no `RETURNING`). Booleans are stored as `TINYINT(1)`. Identifiers
are quoted with backticks.

Two MySQL-specific behaviours to be aware of:

- **Timestamps use `DATETIME(6)`**. Plain `DATETIME` truncates fractional
  seconds, which would cause `created_at` drift on round-trip. Microsecond
  precision avoids it.
- **`DATETIME` columns are written and read in the local timezone**. DBDish::mysql
  parses `DATETIME` values with `:timezone($*TZ)`, so `coerce-write` emits
  local-TZ strings to keep round-trips symmetric.

#### libmysqlclient discovery

DBDish::mysql searches for `libmysqlclient` versions 16..21 by default. Recent
installs ship version 24+, which falls outside that range. ORM::ActiveRecord's
`MySqlAdapter.connect` works around this by setting `DBIISH_MYSQL_LIB`
automatically, checking common Homebrew/apt paths.

If it still can't find the library, set `DBIISH_MYSQL_LIB` yourself:

```shell
# macOS / Homebrew
export DBIISH_MYSQL_LIB=$(brew --prefix mysql-client)/lib/libmysqlclient.dylib

# Debian/Ubuntu
export DBIISH_MYSQL_LIB=/usr/lib/x86_64-linux-gnu/libmysqlclient.so
```

### SQLite

Uses `?` bind placeholders. Surrogate keys come from
`INSERT … RETURNING id` on SQLite ≥ 3.35; older versions fall back to
`last_insert_rowid()`. Schema introspection goes through `pragma_table_info`.
Booleans are stored as `INTEGER 0/1` and dates/datetimes as ISO `TEXT`.

SQLite requires `LIMIT` whenever `OFFSET` is used, so the adapter emits
`LIMIT -1 OFFSET N` when an offset is set without a limit. (`-1` means
unbounded in SQLite.)

The `database` field accepts a file path (created on first connect) or the
literal `":memory:"` for an ephemeral in-process database — useful in tests.
