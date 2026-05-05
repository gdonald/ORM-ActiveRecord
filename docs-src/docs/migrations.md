# Migrations

ORM::ActiveRecord includes commands to migrate your database.  Migrations include adding and removing tables as well as adding and removing columns and indexes.

Migration files should contain two methods: an `up` and a `down`.  The `up` method is the forward change you want to perform.  The `down` method should contain what you want to happen if you decide to rollback the changes from the `up` method.

## Examples

db/migrate/001-create-users.raku

```perl6
use ORM::ActiveRecord::Migration;

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
use ORM::ActiveRecord::Migration;

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

## Timestamps

Most tables benefit from `created_at` and `updated_at` columns. ORM::ActiveRecord
adds them with `add-timestamps` and manages them automatically: `created_at` is
set on insert, `updated_at` is set on every save. The columns are
`TIMESTAMPTZ NOT NULL DEFAULT now()`.

```perl6
use ORM::ActiveRecord::Migration;

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
