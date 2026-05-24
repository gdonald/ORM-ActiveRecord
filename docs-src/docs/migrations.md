# Migrations

ORM::ActiveRecord includes commands to migrate your database.  Migrations include adding and removing tables as well as adding and removing columns and indexes.

Migration files contain either a single `change` method (the recommended
form, see [Reversible migrations](#reversible-migrations)) or a pair of
`up` and `down` methods.  The `up` method is the forward change you want to
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

| Type         | Notes                                                                  |
| ------------ | ---------------------------------------------------------------------- |
| `:string`    | Variable-length text. Accepts `limit => N` (defaults to 255).          |
| `:text`      | Unbounded text. No `limit`.                                            |
| `:integer`   | Whole-number column.                                                   |
| `:boolean`   | True/False. Storage varies by adapter (`BOOLEAN`, `TINYINT(1)`, `INTEGER 0/1`). |
| `:datetime`  | Timestamp without explicit timezone semantics.                         |
| `:timestamp` | Synonym for `:datetime`.                                               |
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

## Timestamps

Most tables benefit from `created_at` and `updated_at` columns. ORM::ActiveRecord
adds them with `add-timestamps` and manages them automatically: `created_at` is
set on insert, `updated_at` is set on every save.

The exact column type is adapter-aware:

| Adapter    | Generated DDL                                                                |
| ---------- | ---------------------------------------------------------------------------- |
| PostgreSQL | `TIMESTAMPTZ NOT NULL DEFAULT now()`                                         |
| MySQL      | `DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)` (microsecond precision)  |
| SQLite     | `DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP`                                |

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
inside, in reverse order. It is the easiest way to write a migration that
undoes an earlier one without copy-pasting the original:

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

## Run Migrations

New migrations can be ran using the provided `ar` command.  It its most simple form `ar` will run all outstanding `up` methods.

```shell
$ ar
```

Other migration options include the ability to only migrate `up` or `down` a specific number of migrations:

```shell
$ ar up      # runs all pending migrations
$ ar down    # resets all migrations, be careful!
$ ar up:1    # runs 1 pending migrations
$ ar down:2  # resets 2 previously completed migrations
```

## Reset

`ar reset` drops every table in the database (including the bookkeeping
`migrations` table) so the next `ar` run reapplies every migration from
scratch. The drop ignores foreign-key dependencies: PostgreSQL uses
`DROP TABLE ... CASCADE`, MySQL temporarily flips `FOREIGN_KEY_CHECKS = 0`,
SQLite turns off `PRAGMA foreign_keys`.

Reset is a deliberate, destructive action. It prints the tables it is
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

| Reply            | Outcome      |
| ---------------- | ------------ |
| `Y` / `y`        | Drop tables  |
| `<enter>` (empty)| Drop tables  |
| `n`              | Abort        |
| anything else    | Abort        |

To bypass the prompt in scripts, pass `--yes` (or set `AR_ASSUME_YES=1`):

```shell
$ ar reset --yes
$ AR_ASSUME_YES=1 ar reset
```

`ar reset` does **not** re-run migrations. Pair it with a plain `ar` when
you want a clean slate plus a fresh schema:

```shell
$ ar reset --yes && ar
```
