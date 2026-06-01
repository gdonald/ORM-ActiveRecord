# Adapters

ORM::ActiveRecord supports three database backends: PostgreSQL, MySQL, and
SQLite. Tests run against all three on every CI build. Application code is the
same regardless of the backend.

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
cp config/application.json-postgresql-example config/application.json
cp config/application.json-mysql-example      config/application.json
cp config/application.json-sqlite-example     config/application.json
```

The shape is per-environment, with one or more named connections per
environment (`primary` is the default connection):

```json
{
  "test": {
    "parallel": 4,
    "primary": {
      "adapter": "pg",
      "host": "localhost",
      "port": 5432,
      "name": "ar_test",
      "user": "postgres",
      "password": "",
      "schema": "public"
    }
  },
  "development": {
    "primary": {
      "adapter": "pg",
      "name": "ar_development",
      "user": "postgres"
    }
  }
}
```

`adapter` must be one of `pg` / `mysql` / `sqlite` (the same aliases as
`DATABASE_URL` schemes are accepted). MySQL has no separate schema concept —
the `name` field IS the schema. SQLite only needs `name` (the file path) or
`":memory:"`.

The active environment is chosen by `AR_ENV` (`bin/ar` defaults to
`development`; the test suite uses `test`). When `DATABASE_URL` is set it
overrides the active environment's `primary` connection; any other named
connection is still resolved from `config/application.json`.

> **Legacy flat config.** The older single-database shape — `{ "db": { … } }`
> — is still accepted and auto-promoted to the active environment's `primary`
> connection (with a deprecation warning). Migrate to the per-environment shape.

### Multiple databases

An environment may declare more than one named connection:

```json
{
  "production": {
    "primary":   { "adapter": "pg", "name": "app",        "user": "app" },
    "analytics": { "adapter": "pg", "name": "app_events",  "user": "app" }
  }
}
```

`DB.shared(:name<analytics>)` returns a connection by name; `DB.shared` (no
name) is `primary`. Bind a model to a non-primary connection with the
`connects-to` class method:

```raku
class Event is Model {
  Event.connects-to('analytics');
}
```

Every query a bound model runs — class finders, relations, and its instances'
saves — routes to that connection. Unbound models use `primary`.

The `parallel` key (test environment only) sets how many per-worker database
copies `ar createdb --parallel` / `test.raku --parallel` create; see
[Tests](tests.md).

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

## Connection lifecycle

The adapter on `DB.shared` exposes four lifecycle primitives. The shared
handle connects lazily on first use, so most callers never touch these — they
exist for tests, long-running daemons, and code that needs to recycle a
connection after an out-of-band drop.

```perl6
use ORM::ActiveRecord::DB;

my $db = DB.shared;

$db.exec('SELECT 1');     # forces the lazy connect
$db.is-connected;         # True

$db.disconnect;           # closes the handle, returns True
$db.is-connected;         # False
$db.disconnect;           # no-op on an already-closed handle, returns False

$db.reconnect;            # disconnect (if needed) + connect
$db.is-connected;         # True
```

**Auto-reconnect** — once a handle has been built, the next `exec` /
`exec-stmt` after a `disconnect` will re-establish the connection
automatically. The example above could drop the explicit `reconnect` call
and the next query would still succeed.

```perl6
$db.disconnect;
my @rows = $db.exec('SELECT 2');   # exec auto-reconnects, returns 2
```

## Raw SQL with bound parameters

`sanitize-sql` and `sanitize-sql-array` turn a SQL fragment + values into a
ready-to-execute statement with adapter-correct placeholders. They're how
ORM::ActiveRecord avoids string-interpolating values into SQL internally; the
same helpers are available for application code that needs to drop down to
raw SQL.

### Positional `?` placeholders

```perl6
my $stmt = DB.shared.sanitize-sql-array([
  'name = ? AND age = ?',
  'Bob', 30,
]);

DB.shared.exec-stmt($stmt);
```

Each `?` consumes the next value in order. PostgreSQL rewrites them to `$N`;
MySQL and SQLite keep them as `?`. An arity mismatch (too many or too few
values for the `?`s in the template) raises.

### Named `:name` placeholders

```perl6
my $stmt = DB.shared.sanitize-sql-array([
  'name = :name AND age = :age',
  { name => 'Bob', age => 30 },
]);
```

Names that appear in the template but are missing from the hash raise.
You can't mix `?` and `:name` in the same template.

### String-literal preservation

Anything inside single quotes — including `?` characters that look like
placeholders, escaped quotes (`''`), and `:name`-shaped tokens — is passed
through verbatim. `sanitize-sql-array` only substitutes placeholders that
appear outside string literals.

```perl6
DB.shared.sanitize-sql-array([
  q{name = ? AND label = '???' AND tag = ':notbound'},
  'Bob',
]);
# → only one ? was actually a placeholder; one bind, 'Bob'
```

### `sanitize-sql` dispatch

`sanitize-sql` accepts any of three shapes and dispatches on type:

| Input        | Behavior                                                          |
| ------------ | ----------------------------------------------------------------- |
| `Str`        | Wraps the SQL with no binds — useful for static `SELECT 1`-style queries. |
| `Positional` | Equivalent to `sanitize-sql-array`.                               |
| `SqlStmt`    | Returned unchanged.                                               |

