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

| Type         | Notes                                                                                                                                                          |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:string`    | Variable-length text. Accepts `limit => N` (defaults to 255).                                                                                                  |
| `:text`      | Unbounded text. No `limit`.                                                                                                                                    |
| `:integer`   | Whole-number column.                                                                                                                                           |
| `:boolean`   | True/False. Storage varies by adapter (`BOOLEAN`, `TINYINT(1)`, `INTEGER 0/1`).                                                                                |
| `:datetime`  | Timestamp without explicit timezone semantics.                                                                                                                 |
| `:timestamp` | Synonym for `:datetime`.                                                                                                                                       |
| `:reference` | Foreign-key column. The column declared as `user => { :reference }` becomes `user_id INTEGER` plus an index. See the `pages` / `subscriptions` examples above. |

Every column type accepts a `default => $value` option to set a column-level
default.

```perl6
self.create-table: 'articles', [
  title       => { :string, limit => 64 },
  body        => { :text },
  view_count  => { :integer, default => 0 },
  published   => { :boolean, default => False },
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
`add-column` ↔ `remove-column`, `add-index` ↔ `remove-index`,
`add-timestamps` ↔ `remove-timestamps`. Instead of writing both `up` and `down`,
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

## The `ar` command

`ar` is the command-line tool for creating, migrating, and checking your
database(s). It reads the same configuration as the rest of the ORM
(`DATABASE_URL`, or `config/application.json` — see [Adapters](adapters.md)).

| Command            | What it does                                                                 |
| ------------------ | ---------------------------------------------------------------------------- |
| `ar`               | Run all outstanding `up` migrations (same as `ar migrate`).                  |
| `ar migrate`       | Run all outstanding `up` migrations against the configured database(s).      |
| `ar createdb`      | Create the configured database(s); does **not** migrate.                    |
| `ar check`         | Report whether the database(s) exist and are fully migrated; exit non-zero if not. Changes nothing. |
| `ar up[:N]`        | Run all pending migrations, or just `N` of them.                             |
| `ar down[:N]`      | Roll back all migrations, or just `N` of them.                               |
| `ar reset [--yes]` | Drop every table (see [Reset](#reset)).                                      |
| `ar --version`     | Print the installed version.                                                 |
| `ar --help`        | Print usage.                                                                 |

## Run Migrations

With no arguments, `ar` runs all outstanding `up` methods:

```shell
$ ar
```

You can also migrate `up` or `down` a specific number of migrations:

```shell
$ ar up      # runs all pending migrations
$ ar down    # rolls back all migrations
$ ar up:1    # runs 1 pending migration
$ ar down:2  # resets 2 previously completed migrations
```

## Creating databases

`ar createdb` creates the database(s) named in your configuration without
running any migrations — useful for a fresh checkout before the first `ar`:

```shell
$ ar createdb     # create the configured database(s)
$ ar              # then migrate them
```

For a multi-database config (more than one named connection in the active
environment) it creates every one. SQLite files are created on first connect,
so `createdb` is effectively a no-op there.

## Checking readiness

`ar check` verifies, without changing anything, that every database the active
environment expects exists and has all migrations applied. It exits non-zero
and prints a single summary if anything is missing or behind:

```shell
$ ar check
Databases not ready:
  - missing database: app_production
  - unrun migrations: app_events
Run `ar createdb` and `ar migrate` first.
```

## Parallel test databases

`createdb`, `migrate`, and `check` accept `--parallel`, which targets the test
environment's per-worker database copies instead of the single base database.
The worker count comes from the test environment's `parallel` key in
`config/application.json`:

```shell
$ ar createdb --parallel    # create the N per-worker copies
$ ar migrate  --parallel    # migrate them
$ ar check    --parallel    # verify all N are ready
```

This is the machinery behind parallel test runs — see [Tests](tests.md).

## Reset

`ar reset` drops every table in the database (including the bookkeeping
`migrations` table) so the next `ar` run reapplies every migration from
scratch. The drop ignores foreign-key dependencies: PostgreSQL uses
`DROP TABLE ... CASCADE`, MySQL temporarily flips `FOREIGN_KEY_CHECKS = 0`,
SQLite turns off `PRAGMA foreign_keys`.

Reset is destructive. It prints the tables it is
about to drop and prompts:

```shell
$ ar reset
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
$ ar reset --yes
$ AR_ASSUME_YES=1 ar reset
```

`ar reset` does **not** re-run migrations. Pair it with a plain `ar` to drop
all tables and re-run every migration:

```shell
$ ar reset --yes && ar
```
