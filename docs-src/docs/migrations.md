# Migrations

ORM::ActiveRecord includes commands to migrate your database.  Migrations include adding and removing tables as well as adding and removing columns and indexes.

Migration files contain either a single `change` method (see
[Reversible migrations](#reversible-migrations)) or a pair of `up` and `down`
methods.  The `up` method is the forward change you want to
perform.  The `down` method should contain what you want to happen if you
decide to rollback the changes from the `up` method.

## Examples

db/migrate/001-create-users.raku

```perl6
use ORM::ActiveRecord::Schema::Migration;

class CreateUsers is Migration {
  method up {
    self.create-table: 'users', [
      fname => { :string, limit => 32 },
      lname => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'users';
  }
}
```

db/migrate/002-create-pages.raku

```perl6
use ORM::ActiveRecord::Schema::Migration;

class CreatePages is Migration {
  method up {
    self.create-table: 'pages', [
      user => { :reference },
      name => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'pages';
  }
}
```

## Column types

`create-table` and `add-column` accept the same column-type vocabulary. The
canonical name (the adjective on the right-hand side) is what you pass; the
DDL produced is adapter-aware (see [Adapters](adapters.md) for the per-engine
differences).

| Type          | Notes                                                                                                                                                          |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:string`     | Variable-length text. Accepts `limit => N` (defaults to 255).                                                                                                  |
| `:text`       | Unbounded text. No `limit`.                                                                                                                                    |
| `:integer`    | 32-bit whole number.                                                                                                                                           |
| `:bigint`     | 64-bit whole number. (SQLite stores all integers as 64-bit `INTEGER`.)                                                                                         |
| `:smallint`   | 16-bit whole number.                                                                                                                                           |
| `:decimal` / `:numeric` | Exact numeric. Accepts `precision => P` and `scale => S` (ignored by SQLite's affinity).                                                            |
| `:float`      | Approximate floating point (`DOUBLE PRECISION` / `DOUBLE` / `REAL`).                                                                                           |
| `:money`      | Currency. `MONEY` on PostgreSQL, `DECIMAL(19, 4)` on MySQL, `NUMERIC` on SQLite.                                                                               |
| `:boolean`    | True/False. Storage varies by adapter (`BOOLEAN`, `TINYINT(1)`, `INTEGER 0/1`).                                                                                |
| `:date`       | Calendar date.                                                                                                                                                 |
| `:time`       | Time of day.                                                                                                                                                   |
| `:datetime`   | Timestamp without explicit timezone semantics.                                                                                                                 |
| `:timestamp`  | Synonym for `:datetime`.                                                                                                                                        |
| `:timestamptz`| Timestamp with time zone (`TIMESTAMPTZ` on PostgreSQL; falls back to the plain timestamp type on MySQL / SQLite).                                               |
| `:interval`   | Time span. **PostgreSQL only** — MySQL and SQLite raise.                                                                                                        |
| `:uuid`       | `UUID` on PostgreSQL, `CHAR(36)` on MySQL, `TEXT` on SQLite.                                                                                                    |
| `:binary`     | Raw bytes (`BYTEA` / `BLOB`). On MySQL a `limit => N` makes it `VARBINARY(N)`; elsewhere `limit` is ignored.                                                    |
| `:json`       | JSON document. `JSON` on PostgreSQL / MySQL; stored as text on SQLite.                                                                                          |
| `:jsonb`      | Binary JSON. `JSONB` on PostgreSQL; maps to `JSON` on MySQL; stored as text on SQLite. Required for the [`@>` / key-existence operators](models/queries.md#json-jsonb-predicate-operators). |
| `:hstore`     | Key/value store. **PostgreSQL only** (needs the `hstore` extension) — MySQL and SQLite raise.                                                                   |
| `:xml`        | XML document. **PostgreSQL only** — MySQL and SQLite raise.                                                                                                     |
| `:reference`  | Foreign-key column. The column declared as `user => { :reference }` becomes `user_id INTEGER` plus an index. See the `pages` / `subscriptions` examples above.  |

### PostgreSQL-specific types

These are emitted on PostgreSQL only; MySQL and SQLite raise.

| Type / option | Notes |
| ------------- | ----- |
| `array => True` | Modifier on any base type → a PostgreSQL array (`INTEGER[]`, `VARCHAR(255)[]`, …). |
| `:int4range` / `:int8range` / `:numrange` / `:tsrange` / `:tstzrange` / `:daterange` | Range types. |
| `:ltree` | Hierarchical label tree (needs the `ltree` extension). |
| `:inet` / `:cidr` / `:macaddr` | Network address types. |
| `:point` / `:line` / `:lseg` / `:box` / `:path` / `:polygon` / `:circle` | Geometric types. |
| `:tsvector` / `:tsquery` | Full-text search types. |
| `:bit_varying` | Variable-length bit string (`BIT VARYING(N)` with `limit`). |
| `:citext` | Case-insensitive text (needs the `citext` extension). |
| `enum_type => 'name'` | Use an existing PostgreSQL enum type (created with `create-enum`) as the column's type. |

`:bit` (a fixed-length bit string, `BIT(N)` via `limit`) works on PostgreSQL
**and** MySQL; on SQLite it raises.

```perl6
self.create-table: 'places', [
  tags     => { :string, array => True },   # VARCHAR(255)[]
  span      => { :daterange },
  location  => { :point },
  ip        => { :inet },
];
```

### Column constraints

Any column type also accepts these constraint options:

| Option            | Effect                                                                                   |
| ----------------- | ---------------------------------------------------------------------------------------- |
| `null => False`   | Emits `NOT NULL` — enforced on every type (boolean, datetime, …), not just text/integer. |
| `unique => True`  | Emits an inline `UNIQUE` constraint. (SQLite cannot add a `UNIQUE` column via `add-column` — declare it in `create-table`.) |
| `comment => '…'`  | Column comment (`COMMENT ON COLUMN` on PostgreSQL, inline `COMMENT` on MySQL, ignored on SQLite). |

```perl6
self.create-table: 'users', [
  email     => { :string, limit => 128, null => False, unique => True },
  is_active => { :boolean, null => False, default => True },
  ssn       => { :string, comment => 'redacted in logs' },
];
```

### Inline foreign keys

`references => '<table>'` declares a foreign key on the column as named, pointed
at the given table. Unlike `:reference` (which appends `_id` and derives the
target table from the column name), `references` takes the exact column and
target, so it fits a column you have already named:

```perl6
self.create-table: 'comments', [
  body    => { :string, limit => 255 },
  user_id => { :integer, references => 'users', on-delete => 'cascade' },
];
```

| Option                      | Effect                                                              |
| --------------------------- | ------------------------------------------------------------------ |
| `references => '<table>'`   | Target table for the foreign key.                                  |
| `on-delete => '<action>'`   | `cascade`, `nullify`, `restrict`, `set-default`, or `no-action`.   |
| `on-update => '<action>'`   | Same actions as `on-delete`.                                       |
| `fk-name => '<name>'`       | Constraint name. Defaults to `fk_<table>_<column>`.                |
| `fk-primary-key => '<col>'` | Referenced column on the target table. Defaults to `id`.           |

On PostgreSQL and MySQL the constraint is added with `ALTER TABLE`; on SQLite it
is declared inline in the `CREATE TABLE` (SQLite cannot add a foreign key to an
existing table). This is the form `db:schema:dump` emits for SQLite.

Every column type accepts a `default => $value` option to set a column-level
default (see also [function defaults](#function-defaults)).

```perl6
self.create-table: 'articles', [
  title        => { :string, limit => 64 },
  body         => { :text },
  view_count   => { :integer, default => 0 },
  price        => { :decimal, precision => 10, scale => 2 },
  weight       => { :float },
  token        => { :uuid },
  payload      => { :binary },
  published    => { :boolean, default => False },
  published_at => { :datetime },
];
```

## Adding and removing columns

`add-column` adds a single column to an existing table. The column spec uses
the same shape as inside `create-table`:

```perl6
self.add-column: 'games', :year => { :integer };
self.add-column: 'games', :title => { :string, limit => 80 };
```

`remove-column` is the inverse and takes the bare column name:

```perl6
self.remove-column: 'games', :year;
```

A typical pair lives in `up` / `down`:

```perl6
class AddGamesYear is Migration {
  method up {
    self.add-column: 'games', :year => { :integer };
  }

  method down {
    self.remove-column: 'games', :year;
  }
}
```

## Table options

`create-table` and `drop-table` accept options that control how the statement
is emitted.

### `force`

`force => True` drops the table first (with `DROP TABLE IF EXISTS`) so the
`create-table` always starts from a clean slate:

```perl6
self.create-table: 'users', [ name => { :string, limit => 32 } ],
  force => True;
```

`force => 'cascade'` adds `CASCADE` to the drop so dependent objects (views,
foreign keys) go with it. `CASCADE` is PostgreSQL-only; MySQL and SQLite treat
`'cascade'` the same as `True` (a plain `DROP TABLE IF EXISTS`).

```perl6
# PostgreSQL: drops the table and anything depending on it, then recreates
self.create-table: 'users', [ name => { :string, limit => 32 } ],
  force => 'cascade';
```

### `temporary`

`temporary => True` emits `CREATE TEMPORARY TABLE`. The table lives only for the
session that created it and is invisible to other connections:

```perl6
self.create-table: 'scratch', [ payload => { :text } ],
  temporary => True;
```

### `if-not-exists` / `if-exists`

`create-table` takes `if-not-exists => True` (skips the create when the table is
already there) and `drop-table` takes `if-exists => True` (skips the drop when it
is already gone). Both are supported on every adapter:

```perl6
self.create-table: 'users', [ name => { :string } ], if-not-exists => True;
self.drop-table:    'users', :if-exists;
```

`drop-table` also accepts `:cascade` (PostgreSQL) to drop dependents alongside
the table.

### Primary keys

By default `create-table` adds an auto-incrementing integer surrogate key named
`id` (`SERIAL` on PostgreSQL, `INTEGER PRIMARY KEY AUTOINCREMENT` on SQLite,
`INT AUTO_INCREMENT` on MySQL). The `id` and `primary-key` options change that.

#### Custom `id` type

Pass `id => '<type>'` to give the surrogate key a different type. `'uuid'`,
`'bigint'`, `'integer'`, and `'string'` are recognised; anything else falls
through to the adapter's type map.

```perl6
# UUID primary key. PostgreSQL defaults it to gen_random_uuid(); SQLite stores
# it as TEXT and MySQL as CHAR(36), with generation left to the application.
self.create-table: 'documents', [ title => { :string, limit => 128 } ],
  id => 'uuid';

# 64-bit integer surrogate key.
self.create-table: 'events', [ name => { :string, limit => 64 } ],
  id => 'bigint';
```

#### No primary key

`id => False` skips the surrogate column entirely; pair it with
`primary-key => False` for a table with no primary key at all:

```perl6
self.create-table: 'audit_log', [
  message => { :text },
  at      => { :datetime },
], id => False, primary-key => False;
```

#### Renaming the primary key

`primary-key => 'name'` names the surrogate column (and its `PRIMARY KEY`)
something other than `id`:

```perl6
self.create-table: 'users', [ email => { :string, limit => 128 } ],
  primary-key => 'guid';   # → guid SERIAL PRIMARY KEY, no id column
```

#### Composite primary keys

Pass a list to `primary-key` to build a composite key over columns you declare
yourself. A composite key implies `id => False` — no surrogate column is added,
so every key column must appear in the column list:

```perl6
self.create-table: 'order_lines', [
  order_id => { :integer },
  id       => { :integer },
  sku      => { :string, limit => 32 },
], id => False, primary-key => ['order_id', 'id'];
```

The key columns are emitted in the order given.

> These options shape the table DDL. A model maps onto a composite key with
> `primary-key`; see the composite primary keys section of the finders guide.

## Join tables

`create-join-table` builds the two-column table that backs a many-to-many
association. The table name is the two arguments sorted and joined with `_`, and
each column is `<singular>_id NOT NULL`. There is no `id` primary key:

```perl6
class JoinPostsAndTags is Migration {
  method change {
    self.create-join-table: 'posts', 'tags';   # → posts_tags (post_id, tag_id)
  }
}
```

`drop-join-table` is the inverse and derives the same name. Inside `change`,
`create-join-table` auto-inverts to `drop-join-table`; a standalone
`drop-join-table` is irreversible (supply explicit `up` / `down`).

| Option       | Default                   | Effect                                                   |
| ------------ | ------------------------- | -------------------------------------------------------- |
| `table-name` | sorted `<a>_<b>`          | Override the generated join-table name.                  |
| `null`       | `False`                   | Set to `True` to allow NULL in the two id columns.       |
| `type`       | `'integer'`               | Override the id column type (e.g. `bigint`).             |

```perl6
self.create-join-table: 'posts', 'tags', table-name => 'taggings';
self.drop-join-table:   'posts', 'tags', table-name => 'taggings';
```

## Bulk table changes

`change-table` yields a block-scoped builder so several alterations to one table
read together. With `bulk => True` the column additions and removals are
coalesced into a single `ALTER TABLE` statement (one table rewrite instead of
several); other operations (indexes, renames, timestamps) run as their own
statements afterward:

```perl6
class WidenUsers is Migration {
  method change {
    self.change-table: 'users', -> $t {
      $t.add-column: :age  => { :integer };
      $t.add-column: :city => { :string, limit => 64 };
      $t.remove-column: 'legacy_flag';
      $t.add-index: :age;
    }, bulk => True;
  }
}
```

The builder exposes `add-column` (alias `column`), `remove-column` (alias
`remove`), `add-index`, `remove-index`, `add-timestamps`, `remove-timestamps`,
`rename-column`, and `add-reference` (alias `add-belongs-to`) — each mirrors the
matching migration method without the leading table argument. Because the
operations are replayed through the normal DSL, a `change-table` built from
reversible operations is itself reversible inside `change`.

SQLite's `ALTER TABLE` permits only one column operation per statement, so
`bulk` there runs each column change on its own; the result is identical, just
not coalesced.

## Column options

`add-column` accepts `if-not-exists => True` and `remove-column` accepts
`if-exists => True`. These are PostgreSQL-only — MySQL and SQLite raise rather
than emit SQL that would not run:

```perl6
self.add-column:    'users', :nickname => { :string }, if-not-exists => True;
self.remove-column: 'users', :nickname, if-exists => True;
```

`add-index` (`if-not-exists`) and `remove-index` (`if-exists`) work on
PostgreSQL and SQLite; MySQL raises:

```perl6
self.add-index:    'users', :email, if-not-exists => True;
self.remove-index: 'users', :email, if-exists => True;
```

### Adapter support

| Operation                       | PostgreSQL | SQLite | MySQL |
| ------------------------------- | :--------: | :----: | :---: |
| `create-table force`            |    yes     |  yes   |  yes  |
| `create-table force: cascade`   |  cascade   | plain  | plain |
| `create-table temporary`        |    yes     |  yes   |  yes  |
| `create-table if-not-exists`    |    yes     |  yes   |  yes  |
| `drop-table if-exists`          |    yes     |  yes   |  yes  |
| `add/remove-column if-[not-]exists` | yes    |   —    |   —   |
| `add/remove-index if-[not-]exists`  | yes    |  yes   |   —   |

## Defaults, generated columns, collation, and comments

`create-table` and `add-column` accept several further per-column options.

### Function defaults

A literal `default => $value` emits a quoted/typed literal. To use a SQL
expression instead (so the database evaluates it on every insert), pass a
block — it is emitted verbatim, unquoted:

```perl6
self.create-table: 'events', [
  name       => { :string, limit => 64 },
  created_at => { :timestamp, default => -> { 'now()' } },
];
```

The block's return value is raw SQL, so use the function spelling your adapter
understands (`now()` on PostgreSQL, `CURRENT_TIMESTAMP(6)` on MySQL,
`CURRENT_TIMESTAMP` on SQLite). A plain `default => 'now()'` would store the
*string* `now()`, not call the function.

### Generated (computed) columns

Pass `as => '<expression>'` to make a column computed from other columns. Add
`stored => True` to persist the value; omit it (or `stored => False`) for a
virtual column computed on read:

```perl6
self.create-table: 'rectangles', [
  width     => { :integer },
  height    => { :integer },
  area      => { :integer, as => 'width * height', stored => True },
  perimeter => { :integer, as => '2 * (width + height)' },   # virtual
];
```

PostgreSQL only supports `STORED` generated columns (before PG 18), so `area`
and `perimeter` are both emitted `STORED` there; MySQL and SQLite honour the
`stored` flag and default to `VIRTUAL`. A generated column cannot also carry a
`default`.

### Collation and charset

`collation => '<name>'` sets a per-column collation; on MySQL you can also pass
`charset => '<name>'`:

```perl6
# PostgreSQL — COLLATE "C"
self.create-table: 'people', [ name => { :string, collation => 'C' } ];

# MySQL — CHARACTER SET utf8mb4 COLLATE utf8mb4_bin
self.create-table: 'people', [
  name => { :string, charset => 'utf8mb4', collation => 'utf8mb4_bin' },
];

# SQLite — COLLATE NOCASE
self.create-table: 'people', [ name => { :text, collation => 'NOCASE' } ];
```

PostgreSQL has no per-column charset (passing `charset` raises); SQLite ignores
`charset` for parity.

### Comments at create time

`comment => '<text>'` on a column, and `comment => '<text>'` on `create-table`
itself, set column and table comments:

```perl6
self.create-table: 'orders', [
  status => { :string, limit => 16, comment => 'pending | shipped | closed' },
], comment => 'one row per checkout';
```

On PostgreSQL these emit `COMMENT ON COLUMN` / `COMMENT ON TABLE` statements
after the table is created; MySQL inlines `COMMENT '...'` on the column and
`COMMENT='...'` on the table. SQLite has no comment concept and silently
ignores both. To change a comment on an existing table, see
[`change-column-comment` / `change-table-comment`](#changing-columns).

### Adapter support

| Option                       | PostgreSQL          | MySQL                 | SQLite               |
| ---------------------------- | ------------------- | --------------------- | -------------------- |
| `default => -> { ... }`      | yes                 | yes                   | yes                  |
| `as` / `stored` (generated)  | `STORED` only       | `STORED` / `VIRTUAL`  | `STORED` / `VIRTUAL` |
| `collation`                  | `COLLATE "name"`    | `COLLATE name`        | `COLLATE name`       |
| `charset`                    | — (raises)          | `CHARACTER SET name`  | ignored              |
| column `comment`             | `COMMENT ON COLUMN` | inline `COMMENT`      | ignored              |
| table `comment`              | `COMMENT ON TABLE`  | `COMMENT=` on table   | ignored              |

## Changing columns

After a table exists, four methods alter the shape of a column in place:

| Method                  | Effect                                                                  |
| ----------------------- | ----------------------------------------------------------------------- |
| `change-column`         | Replace the column's type (and optionally its default / null / comment) |
| `change-column-default` | Set or drop the column's default value                                  |
| `change-column-null`    | Toggle the `NOT NULL` constraint                                        |
| `change-column-comment` | Set or clear the column comment                                         |

```perl6
self.change-column:         'users', 'name', 'text';
self.change-column:         'users', 'name', 'string', limit => 80, null => False;

self.change-column-default: 'orders', 'status', 'pending';
self.change-column-default: 'orders', 'status', Nil;          # drop the default

self.change-column-null:    'users', 'email', False;          # SET NOT NULL
self.change-column-null:    'users', 'email', True;           # DROP NOT NULL
self.change-column-null:    'users', 'label', False, 'unknown';  # backfill, then NOT NULL

self.change-column-comment: 'users', 'email', 'primary contact address';
```

### Reversibility

Inside `change`, only operations whose inverse is unambiguous run on `down`:

| Operation                                 | Reversible in `change`?                           |
| ----------------------------------------- | ------------------------------------------------- |
| `change-column-null(t, c, $bool)`         | Yes — the bool is toggled on `down`               |
| `change-column-default(t, c, :from, :to)` | Yes — `from`/`to` are swapped on `down`           |
| `change-column-comment(t, c, :from, :to)` | Yes — `from`/`to` are swapped on `down`           |
| `change-table-comment(t, :from, :to)`     | Yes — `from`/`to` are swapped on `down`           |
| `change-column`                           | No — raises `X::IrreversibleMigration` on `down`  |
| `change-column-default(t, c, $value)`     | No — raises unless the `from:`/`to:` form is used |
| `change-column-comment(t, c, $value)`     | No — raises unless the `from:`/`to:` form is used |
| `change-table-comment(t, $value)`         | No — raises unless the `from:`/`to:` form is used |

For the irreversible cases, provide explicit `up` / `down` pairs or wrap the
call in `reversible`. The `from:` / `to:` shorthand keeps a default / comment
change inside `change`:

```perl6
class RenameOrderStatus is Migration {
  method change {
    self.change-column-default: 'orders', 'status',
      from => 'pending', to => 'awaiting_review';
  }
}
```

### Table comments

`change-table-comment` sets a comment on the whole table:

```perl6
self.change-table-comment: 'orders', 'one row per checkout';
self.change-table-comment: 'orders', :from('old text'), :to('new text');
```

### Adapter differences

| Operation               | PostgreSQL                    | MySQL                                                                                              | SQLite                                       |
| ----------------------- | ----------------------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `change-column`         | `ALTER ... TYPE`              | `MODIFY COLUMN` (re-emits the column definition with introspected null / default / comment merged) | Not supported — raises                       |
| `change-column-default` | `ALTER ... SET/DROP DEFAULT`  | `ALTER ... SET/DROP DEFAULT`                                                                       | Not supported — raises                       |
| `change-column-null`    | `ALTER ... SET/DROP NOT NULL` | `MODIFY COLUMN` with introspected type                                                             | Not supported — raises                       |
| `change-column-comment` | `COMMENT ON COLUMN ...`       | `MODIFY COLUMN ... COMMENT '...'`                                                                  | Silent no-op (SQLite has no column comments) |
| `change-table-comment`  | `COMMENT ON TABLE ...`        | `ALTER TABLE ... COMMENT = '...'`                                                                  | Silent no-op (SQLite has no table comments)  |

SQLite has no `ALTER COLUMN` and would need a table rebuild for type / default
/ null changes. Those methods raise rather than silently doing the wrong thing
— use `reversible` with raw `execute` if you need parity in a SQLite-only
migration.

## Adding and removing indexes

`add-index` creates an index on a column (or set of columns). The simplest
form indexes one column:

```perl6
self.add-index: 'games', :year;                  # games_year_idx
```

The generated index name is `<table>_<column>_idx`. To make it unique, pass
`{ :unique }` as the value:

```perl6
self.add-index: 'clients', email => { :unique };  # clients_email_idx UNIQUE
```

For composite indexes pass an angle-quoted list of column names. The index
name becomes `<table>_<col1>_<col2>_idx`:

```perl6
self.add-index: 'subscriptions', <user_id magazine_id> => { :unique };
# → subscriptions_user_id_magazine_id_idx UNIQUE
```

`remove-index` mirrors the single-column form and reconstructs the same name
internally:

```perl6
self.remove-index: 'games', :year;
```

### Index options

Both the single-column adverb form (`:email`) and a composite list accept the
same set of named options. Pass `unique` and a custom `name` to control the
flags and the generated identifier:

```perl6
self.add-index: 'users', :email, unique => True, name => 'uniq_user_email';
```

A `where:` predicate produces a partial (conditional) index, and an
`expression:` builds a functional index. Because an expression has no column
to derive a name from, give partial / expression indexes an explicit `name`:

```perl6
self.add-index: 'users', :score,
  where => 'score > 0',
  name  => 'idx_users_positive_score';

self.add-index: 'users',
  expression => 'lower(email)',
  name       => 'idx_users_lower_email';
```

`using:` selects the access method (`btree`, `hash`, `gin`, `gist`, …),
`include:` adds non-key covering columns, `order:` sets the sort direction,
and `opclass:` attaches an operator class. `order:` and `opclass:` accept
either a single value (applied to every column) or a hash keyed by column
name:

```perl6
self.add-index: 'users', :label, using => 'btree';

self.add-index: 'users', :tenant_id,
  include => <email>,
  name    => 'idx_users_tenant_covering';

self.add-index: 'events', <happened_at kind>, order => { happened_at => 'desc' };

self.add-index: 'users', :email,
  opclass => 'text_pattern_ops',
  name    => 'idx_users_email_pattern';
```

On PostgreSQL, `algorithm => 'concurrently'` builds (or drops) the index
without holding a write lock:

```perl6
# PostgreSQL only — raises on SQLite and MySQL
self.add-index: 'users', :active, algorithm => 'concurrently', name => 'idx_users_active';
```

An adapter that does not support a clause raises rather than silently
ignoring it, so this migration throws on SQLite or MySQL instead of creating
a plain index. Drop the `algorithm:` option (or gate the migration on the
adapter) when you need it to run everywhere. The same applies to the other
gated options below.

### Adapter support

Not every clause exists on every database. The simple, composite, unique,
and named forms work everywhere. The rest are gated, and an unsupported
clause raises a clear error rather than emitting broken SQL:

| Option                    | PostgreSQL | SQLite | MySQL |
| ------------------------- | :--------: | :----: | :---: |
| `where:` (partial)        |    yes     |  yes   |   —   |
| `expression:`             |    yes     |  yes   |  yes  |
| `using:` (access method)  |    yes     |   —    |  yes  |
| `include:` (covering)     |    yes     |   —    |   —   |
| `algorithm: concurrently` |    yes     |   —    |   —   |
| `opclass:`                |    yes     |   —    |   —   |

## Renaming tables, columns, indexes

`rename-table` moves a table, `rename-column` renames a column in place, and
`rename-index` renames an existing index. All three are reversible — the
inverse swaps the from / to identifiers, so a `change` method can call them
directly:

```perl6
class RenameAccountToProfile is Migration {
  method change {
    self.rename-table:  'accounts', 'profiles';
    self.rename-column: 'profiles', 'login_name', 'username';
    self.rename-index:  'profiles', 'accounts_username_idx', 'profiles_username_idx';
  }
}
```

`rename-index` takes the table name first because MySQL's `RENAME INDEX`
syntax is rooted at the table. PostgreSQL and SQLite ignore the table name
but follow the same call signature for cross-adapter parity. SQLite has no
native `ALTER INDEX RENAME` — the adapter looks up the original
`CREATE INDEX` SQL, drops it, and re-runs it with the new identifier.

## References

A reference is the "I belong to X" shortcut for a foreign-key column.
`add-reference :user` adds a `user_id` column plus a matching index. The
inverse — `remove-reference :user` — drops the index and the column.

```perl6
class AddUserToPosts is Migration {
  method change {
    self.add-reference: 'posts', 'user';
  }
}
```

`add-belongs-to` is an alias for `add-reference`; `remove-belongs-to` is the
inverse alias. Options accepted by both:

| Option        | Default     | Effect                                                                                            |
| ------------- | ----------- | ------------------------------------------------------------------------------------------------- |
| `null`        | `True`      | Set to `False` to make `<name>_id` (and `<name>_type`) NOT NULL.                                  |
| `index`       | `True`      | Set to `False` to skip the index.                                                                 |
| `unique`      | `False`     | Make the index unique.                                                                            |
| `polymorphic` | `False`     | Add both `<name>_id` and `<name>_type`; the index becomes composite (`<name>_type`, `<name>_id`). |
| `type`        | `'integer'` | Override the integer type (e.g. `bigint`).                                                        |
| `foreign-key` | `False`     | Also add an `ALTER TABLE ... ADD CONSTRAINT FOREIGN KEY` — see below.                             |
| `to-table`    | `<name>s`   | The referenced table when `foreign-key` is set and the inferred plural is wrong.                  |
| `on-delete`   | (none)      | Forwarded to the FK clause; only valid with `foreign-key => True`.                                |
| `on-update`   | (none)      | Same.                                                                                             |
| `fk-name`     | (auto)      | Override the generated FK constraint name.                                                        |

```perl6
self.add-reference: 'comments', 'commentable', polymorphic => True;
self.add-reference: 'orders',   'customer',
  foreign-key => True, on-delete => 'cascade';
```

`add-reference` `index => True` (the default) names the index
`<table>_<name>_id_idx` for a regular reference and
`<table>_<name>_type_<name>_id_idx` for a polymorphic one.

## Foreign keys

`add-foreign-key` and `remove-foreign-key` mutate the FK constraint without
touching the column. Use them when the column already exists (e.g. on a
legacy table) or when you want a constraint between two tables that don't
follow the `<name>s` plural inference.

```perl6
class WireOrdersToCustomers is Migration {
  method change {
    self.add-foreign-key: 'orders', 'customers',
      column    => 'customer_id',
      on-delete => 'cascade',
      on-update => 'restrict';
  }
}
```

Options for `add-foreign-key(from, to, ...)`:

| Option        | Default                    | Effect                                                                                                                      |
| ------------- | -------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `column`      | `<singular_to_table>_id`   | Source column on `from`.                                                                                                    |
| `primary-key` | `id`                       | Target column on `to`.                                                                                                      |
| `name`        | `fk_<from_table>_<column>` | Override the constraint name.                                                                                               |
| `on-delete`   | (none)                     | `cascade`, `nullify` / `set-null`, `set-default`, `restrict`, `no-action`.                                                  |
| `on-update`   | (none)                     | Same vocabulary as `on-delete`.                                                                                             |
| `validate`    | `True`                     | On PostgreSQL, `False` emits `NOT VALID` so the constraint is enforced on new rows only. Other adapters ignore this option. |

`remove-foreign-key` accepts either the explicit `name:` or `to-table:` plus
(optionally) `column:` so it can derive the same name `add-foreign-key`
would have generated:

```perl6
self.remove-foreign-key: 'orders', name => 'orders_cust_fk';
self.remove-foreign-key: 'orders', to-table => 'customers', column => 'customer_id';
```

`validate-foreign-key(table, name)` runs `ALTER TABLE ... VALIDATE
CONSTRAINT` on PostgreSQL (for the deferred `NOT VALID` workflow). On MySQL
it is a no-op because MySQL validates every constraint on creation.

### Reversibility

`add-reference` and `add-foreign-key` are reversible inside `change` —
`down` calls `remove-reference` / `remove-foreign-key` with the same
options. The standalone `remove-reference` and `remove-foreign-key`
operations are irreversible inside `change` (no way to derive the original
options); supply explicit `up` / `down` pairs.

### Adapter differences

| Operation                       | PostgreSQL                        | MySQL                              | SQLite                                            |
| ------------------------------- | --------------------------------- | ---------------------------------- | ------------------------------------------------- |
| `add-reference` (column + idx)  | Yes                               | Yes                                | Yes                                               |
| `add-reference :foreign-key`    | `ALTER TABLE ... ADD CONSTRAINT`  | `ALTER TABLE ... ADD CONSTRAINT`   | Raises — declare the FK in `create-table` instead |
| `add-foreign-key` direct        | Yes                               | Yes                                | Raises — declare the FK in `create-table` instead |
| `remove-foreign-key`            | `ALTER TABLE ... DROP CONSTRAINT` | `ALTER TABLE ... DROP FOREIGN KEY` | Raises                                            |
| `validate :False` (`NOT VALID`) | Yes                               | No-op (always validates)           | n/a                                               |

## Check, unique, and exclusion constraints

These DSL methods emit `ALTER TABLE ... ADD CONSTRAINT` / `DROP CONSTRAINT`
statements for table-level constraints beyond foreign keys.

```perl6
class TightenProducts is Migration {
  method change {
    self.add-check-constraint:  'products', 'price > 0',
      name => 'chk_products_price_positive';

    self.add-unique-constraint: 'products',
      columns => <tenant_id sku>,
      name    => 'uq_products_tenant_sku';
  }
}
```

### `add-check-constraint(table, expression, ...)`

| Option     | Default                   | Effect                                                                                                                       |
| ---------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `name`     | `chk_<table>_<expr-hash>` | Override the constraint name.                                                                                                |
| `validate` | `True`                    | On PostgreSQL, `False` emits `NOT VALID` so the constraint only applies to new rows. On MySQL, `False` emits `NOT ENFORCED`. |

`remove-check-constraint(table, ...)` accepts `name:` *or* `expression:` —
when only the expression is given it re-derives the same name
`add-check-constraint` would have generated:

```perl6
self.remove-check-constraint: 'products', name => 'chk_products_price_positive';
self.remove-check-constraint: 'products', expression => 'price > 0';
```

`validate-check-constraint(table, name)` runs `ALTER TABLE ... VALIDATE
CONSTRAINT` on PostgreSQL (for the deferred `NOT VALID` workflow) and
`ALTER TABLE ... ALTER CHECK name ENFORCED` on MySQL. It is irreversible
inside `change` — supply explicit `up` / `down` if needed.

### `add-unique-constraint(table, ...)`

| Option               | Default                       | Effect                                                          |
| -------------------- | ----------------------------- | --------------------------------------------------------------- |
| `columns`            | (required)                    | List of column names covered by the constraint.                 |
| `name`               | `uq_<table>_<col1>_<col2>...` | Override the constraint name.                                   |
| `deferrable`         | `False`                       | PostgreSQL `DEFERRABLE` — defer checking to end of transaction. |
| `initially-deferred` | `False`                       | Implies `deferrable`; emits `DEFERRABLE INITIALLY DEFERRED`.    |

`remove-unique-constraint(table, ...)` accepts `name:` or `columns:` —
when only `columns:` is given it re-derives the same name:

```perl6
self.remove-unique-constraint: 'products', name => 'uq_products_tenant_sku';
self.remove-unique-constraint: 'products', columns => <tenant_id sku>;
```

### `add-exclusion-constraint(table, expression, ...)` (PostgreSQL only)

| Option               | Default                    | Effect                                                               |
| -------------------- | -------------------------- | -------------------------------------------------------------------- |
| `using`              | `gist`                     | Access method (`gist`, `btree`, `spgist`, etc.).                     |
| `name`               | `excl_<table>_<expr-hash>` | Constraint name.                                                     |
| `where`              | (none)                     | Optional `WHERE (...)` predicate for a partial exclusion constraint. |
| `deferrable`         | `False`                    | Same as for unique constraints.                                      |
| `initially-deferred` | `False`                    | Same as for unique constraints.                                      |

```perl6
self.add-exclusion-constraint: 'reservations',
  'room_id WITH =, during WITH &&',
  using => 'gist',
  name  => 'excl_reservations_room_during';
```

`remove-exclusion-constraint` requires the explicit `name:` (the
expression cannot always be normalised back to the auto-name).

### Reversibility

| Operation                     | Inside `change`                                            |
| ----------------------------- | ---------------------------------------------------------- |
| `add-check-constraint`        | Reversed by `remove-check-constraint` with the same name.  |
| `remove-check-constraint`     | Irreversible — supply explicit `up` / `down`.              |
| `validate-check-constraint`   | Irreversible.                                              |
| `add-unique-constraint`       | Reversed by `remove-unique-constraint` with the same name. |
| `remove-unique-constraint`    | Irreversible.                                              |
| `add-exclusion-constraint`    | Reversed when `name:` is supplied; otherwise irreversible. |
| `remove-exclusion-constraint` | Irreversible.                                              |

### Adapter differences

| Operation                      | PostgreSQL                        | MySQL                            | SQLite                                               |
| ------------------------------ | --------------------------------- | -------------------------------- | ---------------------------------------------------- |
| `add-check-constraint`         | `ALTER TABLE ... ADD CONSTRAINT`  | `ALTER TABLE ... ADD CONSTRAINT` | Raises — declare the CHECK in `create-table` instead |
| `remove-check-constraint`      | `ALTER TABLE ... DROP CONSTRAINT` | `ALTER TABLE ... DROP CHECK`     | Raises                                               |
| `validate-check-constraint`    | `VALIDATE CONSTRAINT`             | `ALTER CHECK name ENFORCED`      | No-op                                                |
| `add-check :validate => False` | `NOT VALID`                       | `NOT ENFORCED`                   | n/a                                                  |
| `add-unique-constraint`        | `ALTER TABLE ... ADD CONSTRAINT`  | `ALTER TABLE ... ADD CONSTRAINT` | Raises — use `add-index :unique => True` instead     |
| `remove-unique-constraint`     | `ALTER TABLE ... DROP CONSTRAINT` | `ALTER TABLE ... DROP INDEX`     | Raises                                               |
| `add-exclusion-constraint`     | `ALTER TABLE ... ADD CONSTRAINT`  | Raises                           | Raises                                               |
| `remove-exclusion-constraint`  | `ALTER TABLE ... DROP CONSTRAINT` | Raises                           | Raises                                               |

## PostgreSQL extensions and enums

Extensions and enum types are PostgreSQL-specific. These DSL methods raise on
MySQL and SQLite, so a migration that needs them is portable only as far as the
server is.

```perl6
class SetUpCatalog is Migration {
  method change {
    self.enable-extension: 'pgcrypto';

    self.create-enum: 'mood', <sad neutral happy>;
  }
}
```

### `enable-extension(name)` / `disable-extension(name, ...)`

`enable-extension` emits `CREATE EXTENSION IF NOT EXISTS "name"`;
`disable-extension` emits `DROP EXTENSION IF EXISTS "name"`. Both are idempotent
at the SQL level, so re-running a migration does not error.

| Option    | Default | Effect                                                       |
| --------- | ------- | ------------------------------------------------------------ |
| `cascade` | `False` | On `disable-extension`, also drop objects that depend on it. |

```perl6
self.enable-extension:  'citext';
self.disable-extension: 'citext', cascade => True;
```

### `create-enum(name, values)` / `drop-enum(name, ...)`

`create-enum` emits `CREATE TYPE name AS ENUM (...)` with the values in the order
given; passing an empty value list raises. `drop-enum` emits `DROP TYPE name`.

| Option      | Default | Effect                                                    |
| ----------- | ------- | --------------------------------------------------------- |
| `if-exists` | `False` | On `drop-enum`, emit `DROP TYPE IF EXISTS` instead.       |

```perl6
self.create-enum: 'mood', <sad neutral happy>;
self.drop-enum:   'mood', if-exists => True;
```

### `add-enum-value(name, value, ...)`

Emits `ALTER TYPE name ADD VALUE 'value'`. By default the value is appended;
`before:` / `after:` position it relative to an existing label (pass at most
one).

| Option          | Default | Effect                                                    |
| --------------- | ------- | --------------------------------------------------------- |
| `before`        | (none)  | Insert the new value immediately before this label.       |
| `after`         | (none)  | Insert the new value immediately after this label.        |
| `if-not-exists` | `False` | Emit `ADD VALUE IF NOT EXISTS` so a repeat run is a no-op. |

```perl6
self.add-enum-value: 'mood', 'ecstatic', after => 'happy';
```

PostgreSQL cannot remove a value from an enum type, so `add-enum-value` is
**irreversible** inside `change` — supply explicit `up` / `down` if you need a
rollback path.

### `rename-enum-value(name, from, to)`

Emits `ALTER TYPE name RENAME VALUE 'from' TO 'to'`. It is reversible inside
`change`: the rollback renames `to` back to `from`.

```perl6
self.rename-enum-value: 'mood', 'neutral', 'meh';
```

### Reversibility

| Operation           | Inside `change`                                  |
| ------------------- | ------------------------------------------------ |
| `enable-extension`  | Reversed by `disable-extension`.                 |
| `disable-extension` | Reversed by `enable-extension`.                  |
| `create-enum`       | Reversed by `drop-enum`.                         |
| `drop-enum`         | Irreversible — supply explicit `up` / `down`.    |
| `add-enum-value`    | Irreversible — PostgreSQL cannot drop a value.   |
| `rename-enum-value` | Reversed by renaming `to` back to `from`.        |

### Adapter differences

| Operation           | PostgreSQL                       | MySQL  | SQLite |
| ------------------- | -------------------------------- | ------ | ------ |
| `enable-extension`  | `CREATE EXTENSION IF NOT EXISTS` | Raises | Raises |
| `disable-extension` | `DROP EXTENSION IF EXISTS`       | Raises | Raises |
| `create-enum`       | `CREATE TYPE ... AS ENUM`        | Raises | Raises |
| `drop-enum`         | `DROP TYPE`                      | Raises | Raises |
| `add-enum-value`    | `ALTER TYPE ... ADD VALUE`       | Raises | Raises |
| `rename-enum-value` | `ALTER TYPE ... RENAME VALUE`    | Raises | Raises |

## Timestamps

`add-timestamps` adds `created_at` and `updated_at` columns and manages them
automatically: `created_at` is set on insert, `updated_at` is set on every
save.

The exact column type is adapter-aware:

| Adapter    | Generated DDL                                                               |
| ---------- | --------------------------------------------------------------------------- |
| PostgreSQL | `TIMESTAMPTZ NOT NULL DEFAULT now()`                                        |
| MySQL      | `DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)` (microsecond precision) |
| SQLite     | `DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP`                               |

```perl6
use ORM::ActiveRecord::Schema::Migration;

class CreateArticles is Migration {
  method up {
    self.create-table: 'articles', [
      title => { :string, limit => 64 },
      body  => { :text },
    ];
    self.add-timestamps: 'articles';
  }

  method down {
    self.drop-table: 'articles';
  }
}
```

You can also declare datetime columns explicitly with `:datetime` (or
`:timestamp`):

```perl6
self.add-column: 'articles', :published_at => { :datetime }
```

To remove the timestamp columns:

```perl6
self.remove-timestamps: 'articles';
```

## Reversible migrations

Most schema operations have an obvious inverse: `create-table` ↔ `drop-table`,
`create-join-table` ↔ `drop-join-table`, `add-column` ↔ `remove-column`,
`add-index` ↔ `remove-index`, `add-timestamps` ↔ `remove-timestamps`. Instead of writing both `up` and `down`,
define a single `change` method and let the runner derive the rollback:

```perl6
use ORM::ActiveRecord::Schema::Migration;

class CreateArticles is Migration {
  method change {
    self.create-table: 'articles', [
      title => { :string, limit => 64 },
      body  => { :text },
    ];
    self.add-timestamps: 'articles';
  }
}
```

Running this migration forward calls each operation in `change` in order.
Rolling it back records each call, then plays the inverses in reverse order
— so `articles` loses its timestamps first, then the table is dropped.

### `reversible` for asymmetric blocks

When an operation needs different code in each direction (typically raw
SQL), wrap it in `reversible`. The block is invoked with a direction
helper that exposes `up` and `down`:

```perl6
class BackfillStatus is Migration {
  method change {
    self.add-column: 'orders', :status => { :string, default => 'pending' };

    self.reversible: -> $dir {
      $dir.up:   { self.execute("UPDATE orders SET status = 'legacy' WHERE created_at < '2025-01-01'") };
      $dir.down: { self.execute("UPDATE orders SET status = 'pending' WHERE status = 'legacy'") };
    };
  }
}
```

Going up adds the column then runs the up-block. Going down runs the
down-block first, then removes the column.

### `revert` to undo a previous block

`revert` takes a block and performs the *inverse* of every operation
inside, in reverse order. It undoes an earlier migration without copy-pasting
the original:

```perl6
class RemoveLegacyAuditLog is Migration {
  method change {
    self.revert: -> {
      self.create-table: 'legacy_audit_log', [
        message => { :text },
      ];
    };
  }
}
```

Up: drops the `legacy_audit_log` table.
Down: re-creates it with the original definition.

### `execute` is irreversible inside `change`

`execute` runs raw SQL. There is no way to derive its inverse
automatically, so calling it inside `change` makes the migration
irreversible — the rollback will raise `X::IrreversibleMigration`. Either
provide an `up`/`down` pair, or wrap the SQL in `reversible` and supply
both directions.

## Irreversible migrations

Some forward changes can't be undone automatically — a destructive drop, a
column rewrite that loses data, an enum-narrowing. Mark the `down` method as
irreversible by calling `self.irreversible-migration`:

```perl6
class DropLegacyAuditLog is Migration {
  method up {
    self.drop-table: 'legacy_audit_log';
  }

  method down {
    self.irreversible-migration;
  }
}
```

The runner reports the offending file and aborts the rollback if it ever
hits this. See [Errors &raquo; X::IrreversibleMigration](errors.md#xirreversiblemigration).

## Raw SQL and guards

### `execute` raw SQL

`execute` runs an arbitrary SQL string against the migration's connection.
Use it for anything the DSL doesn't cover:

```perl6
self.execute('UPDATE users SET role = 0 WHERE role IS NULL');
```

It is irreversible inside `change` (see [above](#execute-is-irreversible-inside-change)) —
give it an `up`/`down` pair or wrap it in `reversible`.

### `disable-ddl-transaction`

By default the runner wraps each migration in a `BEGIN` / `COMMIT`. Some
statements can't run inside a transaction — most notably
`CREATE INDEX CONCURRENTLY` on PostgreSQL. Override `disable-ddl-transaction`
to return `True` so the runner skips the wrapping for that migration:

```perl6
class AddIndexConcurrently is Migration {
  method disable-ddl-transaction { True }

  method change {
    self.add-index: 'users', :email, algorithm => :concurrently;
  }
}
```

Without a wrapping transaction the migration is **not** atomic — if it fails
partway, the already-applied statements stay applied.

### `safety-assured`

`safety-assured` runs its block unchanged. This ORM enforces no
strong-migration safety checks, so the helper exists for API parity and to
mark intent in migrations ported from Rails:

```perl6
self.safety-assured: -> {
  self.execute('ALTER TABLE orders DROP COLUMN legacy_total');
};
```

The wrapped operations record normally, so reversibility is unaffected.

### Reporter helpers

Three helpers write progress to standard output:

```perl6
self.announce('backfilling order totals');     # == backfilling order totals ====...
self.say('starting');                           # -- starting
self.say('rebuilt cache', :subitem);            #    -> rebuilt cache

# Prints the message, runs the block, then reports elapsed time — and, when
# the block returns an Int, the row count. Returns the block's result.
my $rows = self.say-with-time('migrating data', -> {
  self.execute('UPDATE orders SET total = subtotal + tax');
});
```

Wrap any of them in `suppress-messages` to silence the output (the block's
result is still returned):

```perl6
self.suppress-messages: -> {
  self.say('this is not printed');
};
```

## Schema introspection

The adapter can report a table's catalog metadata beyond its columns:

```perl6
my $db = DB.shared;

$db.get-indexes(table => 'users');
# ({ name => 'users_email_idx', unique => True, columns => ['email'] }, ...)

$db.get-constraints(table => 'orders');
# ({ name => 'fk_orders_user_id', type => 'foreign-key' },
#  { name => 'orders_pkey',       type => 'primary-key' }, ...)

$db.get-sequences;        # ('orders_id_seq', 'users_id_seq')  (PostgreSQL)
```

`get-constraints` reports a canonical `type` of `foreign-key`, `check`,
`unique`, `primary-key`, or `exclusion`. Coverage varies by engine: SQLite
cannot introspect `CHECK` constraints, and `get-sequences` is PostgreSQL's
sequence list, SQLite's `AUTOINCREMENT` tables, and empty on MySQL.

### Schema cache

`SchemaCache` snapshots the whole schema (every table's columns, indexes, and
constraints, plus sequences) so an app can skip live introspection on boot.

```perl6
use ORM::ActiveRecord::Schema::Cache;

# Dump on deploy:
SchemaCache.new.dump(path => 'db/schema_cache.json');

# Load on boot — no database round-trips:
my $cache = SchemaCache.new.load(path => 'db/schema_cache.json');
$cache.table-names;
$cache.columns-for('users');       # ({ name => 'id', type => 'integer' }, ...)
$cache.indexes-for('users');
$cache.constraints-for('users');
```

`serialize` / `deserialize` do the same round-trip through a JSON string
instead of a file.

## The `active-record` command

`active-record` is the command-line tool for creating, migrating, and checking your
database(s). It reads the same configuration as the rest of the ORM
(`DATABASE_URL`, or `config/application.json` — see [Adapters](adapters.md)).

| Command            | What it does                                                                                        |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| `active-record`               | Run all outstanding `up` migrations (same as `active-record migrate`).                                         |
| `active-record migrate`       | Run all outstanding `up` migrations against the configured database(s).                             |
| `active-record createdb`      | Create the configured database(s); does **not** migrate.                                            |
| `active-record check`         | Report whether the database(s) exist and are fully migrated; exit non-zero if not. Changes nothing. |
| `active-record up[:N]`        | Run all pending migrations, or just `N` of them.                                                    |
| `active-record down[:N]`      | Roll back all migrations, or just `N` of them.                                                      |
| `active-record reset [--yes]` | Drop every table (see [Reset](#reset)).                                                             |
| `active-record --version`     | Print the installed version.                                                                        |
| `active-record --help`        | Print usage.                                                                                        |

## Run Migrations

With no arguments, `active-record` runs all outstanding `up` methods:

```shell
$ active-record
```

You can also migrate `up` or `down` a specific number of migrations:

```shell
$ active-record up      # runs all pending migrations
$ active-record down    # rolls back all migrations
$ active-record up:1    # runs 1 pending migration
$ active-record down:2  # resets 2 previously completed migrations
```

## Creating databases

`active-record createdb` creates the database(s) named in your configuration without
running any migrations — useful for a fresh checkout before the first `active-record`:

```shell
$ active-record createdb     # create the configured database(s)
$ active-record              # then migrate them
```

For a multi-database config (more than one named connection in the active
environment) it creates every one. SQLite files are created on first connect,
so `createdb` is effectively a no-op there.

## Checking readiness

`active-record check` verifies, without changing anything, that every database the active
environment expects exists and has all migrations applied. It exits non-zero
and prints a single summary if anything is missing or behind:

```shell
$ active-record check
Databases not ready:
  - missing database: app_production
  - unrun migrations: app_events
Run `active-record createdb` and `active-record migrate` first.
```

## Parallel test databases

`createdb`, `migrate`, and `check` accept `--parallel`, which targets the test
environment's per-worker database copies instead of the single base database.
The worker count comes from the test environment's `parallel` key in
`config/application.json`:

```shell
$ active-record createdb --parallel    # create the N per-worker copies
$ active-record migrate  --parallel    # migrate them
$ active-record check    --parallel    # verify all N are ready
```

This is the machinery behind parallel test runs — see [Tests](tests.md).

## Reset

`active-record reset` drops every table in the database (including the bookkeeping
`migrations` table) so the next `active-record` run reapplies every migration from
scratch. The drop ignores foreign-key dependencies: PostgreSQL uses
`DROP TABLE ... CASCADE`, MySQL temporarily flips `FOREIGN_KEY_CHECKS = 0`,
SQLite turns off `PRAGMA foreign_keys`.

Reset is destructive. It prints the tables it is
about to drop and prompts:

```shell
$ active-record reset
About to DROP these tables:
  articles
  books
  …
  users
Proceed? [Y/n]
```

Pressing `Y` or `Enter` proceeds (the default is yes). Anything else
aborts immediately:

| Reply             | Outcome     |
| ----------------- | ----------- |
| `Y` / `y`         | Drop tables |
| `<enter>` (empty) | Drop tables |
| `n`               | Abort       |
| anything else     | Abort       |

To bypass the prompt in scripts, pass `--yes` (or set `AR_ASSUME_YES=1`):

```shell
$ active-record reset --yes
$ AR_ASSUME_YES=1 active-record reset
```

`active-record reset` does **not** re-run migrations. Pair it with a plain `active-record` to drop
all tables and re-run every migration:

```shell
$ active-record reset --yes && active-record
```
