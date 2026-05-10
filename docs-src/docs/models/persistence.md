# Persistence

ORM::ActiveRecord exposes both quiet (return `False` on failure) and loud
(raise an exception on failure) variants of the persistence methods. Use
whichever fits the situation: forms and user-driven flows usually want the
quiet variants so they can re-render with errors, while scripts, callbacks,
and worker code usually want the loud variants so failures aren't silently
swallowed.

## Save and Update

`save` and `update` return `True` on success or `False` if validation failed.
Inspect `errors` to see what went wrong.

```perl6
my $user = User.new;
$user.fname = '';

unless $user.save {
  for $user.errors.errors -> $e {
    say $e.field.name ~ ' ' ~ $e.message;
  }
}
```

`save-or-die` and `update-or-die` raise `X::RecordInvalid` instead. The
exception carries the failing record and a list of human-readable messages.

```perl6
use ORM::ActiveRecord::Errors::X;

try {
  User.create-or-die({fname => ''});

  CATCH {
    when X::RecordInvalid {
      say .message;        # Validation failed: fname must be present
      say .messages;       # (fname must be present)
      say .record.fname;   # ''
    }
  }
}
```

`create-or-die` is a class-level convenience that builds the record, runs
validations, and raises if it could not be saved.

## Build

`build` constructs an in-memory record without touching the database. It's
the right choice when you want to populate a record, run validations against
it, and only save once everything checks out.

```perl6
my $user = User.build({fname => 'Greg', lname => 'Donald'});

$user.is-valid;     # True / False — runs validators without persisting
$user.id;           # 0 — unsaved
$user.save;         # persists; id becomes the new surrogate key
```

`build` with no arguments returns a record with default attributes:

```perl6
my $blank = User.build;
$blank.fname = 'Alice';
$blank.save;
```

The difference from `create`: `create` builds **and** saves in one step (and
returns whether the save succeeded via the resulting record's `id`), while
`build` is purely in-memory. Reach for `build` when you need to inspect or
mutate the record before deciding to save.

## Destroy and Delete

`destroy` removes the record from the database **and** fires the
`before-destroy` and `after-destroy` callbacks. Use it when associated cleanup,
logging, or notifications need to run.

```perl6
class Page is Model {
  submethod BUILD {
    self.after-destroy: -> { say "Page #{self.id} torn down" };
  }
}

my $page = Page.create({name => 'Welcome'});
$page.destroy;        # fires the after-destroy callback
say $page.id;         # 0  -- the in-memory record's id is cleared
```

`delete` issues the `DELETE` directly without callbacks. Use it when you
want a side-effect-free removal (for example, in tests or in a destroy
callback for a parent record).

```perl6
$page.delete;         # no callbacks, single SQL DELETE
```

`destroy-all` is a class-level convenience that wipes every row in the table
without instantiating records or firing per-row callbacks.

```perl6
Page.destroy-all;
```

## Automatic Timestamps

If a table has `created_at` and/or `updated_at` columns, ORM::ActiveRecord
manages them for you. `created_at` is set on insert; `updated_at` is set on
every save (insert and update).

See [Migrations &raquo; Timestamps](../migrations.md#timestamps) for the
column setup.
