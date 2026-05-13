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

## Cloning and Copying

`dup` returns a new, unsaved copy of the record with `id`, `created_at`,
and `updated_at` cleared. The new instance is fresh: not persisted, not
readonly, not destroyed. Use it when you need to fork a record into a
second row without manually copying every attribute.

```perl6
my $orig = User.create({fname => 'Greg', lname => 'Donald'});
my $copy = $orig.dup;

$copy.is-new-record;   # True
$copy.id;              # 0
$copy.fname;           # 'Greg'

$copy.fname = 'Greg2';
$copy.save;            # inserts a new row
$orig.fname;           # still 'Greg'
```

`clone` returns a shallow copy that **preserves** the `id` and the
`readonly` flag. Mutating attributes on the clone does not affect the
original.

```perl6
my $u = User.create({fname => 'Greg'});
my $c = $u.clone;
$c.id == $u.id;        # True
$c.fname = 'Bob';
$u.fname;              # 'Greg' — unchanged
```

`becomes(Klass)` returns an instance of `Klass` carrying the receiver's
`id` and attributes. It is the building block for Single-Table Inheritance
(STI) casts — re-instantiating a row through a different subclass so that
subclass-specific behavior applies.

```perl6
my $v = Vehicle.find($id);
my $car = $v.becomes(Car);   # same id, same attrs, Car methods now in scope
```

`becomes-or-die(Klass)` does the same and additionally writes the new
class name into the `type` column when the table has one, mirroring
Rails' `becomes!` for STI.

```perl6
my $car = $v.becomes-or-die(Car);
$car.read-attribute('type');   # 'Car'
$car.save;                     # persists the type change
```

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

## Attribute Access

A record exposes its attributes in several complementary ways.

`assign-attributes` mass-assigns from a hash without saving. It returns the
record so you can chain it.

```perl6
my $user = User.build;
$user.assign-attributes({fname => 'Greg', lname => 'Donald'});
$user.save;
```

`attributes = %hash` is the setter alias that delegates to
`assign-attributes`.

```perl6
my $user = User.build;
$user.attributes = {fname => 'Greg', lname => 'Donald'};
```

`read-attribute` / `write-attribute` are explicit getters / setters by name.

```perl6
$user.read-attribute('fname');         # 'Greg'
$user.write-attribute('fname', 'Bob'); # 'Bob'
```

The model also supports indexer access via `[]` and `[]=`, including the
`:exists` adverb.

```perl6
$user<fname>;             # 'Bob'
$user<fname> = 'Alice';
$user<fname>:exists;      # True
$user<bogus>:exists;      # False
```

`is-attribute-present` returns `True` when the attribute exists and has a
non-blank value. It follows the same rules as Rails' `present?`: zero counts
as present, but `False`, the empty string, an empty hash, or an empty array
do not.

```perl6
$user.is-attribute-present('fname');   # True
$user.is-attribute-present('bogus');   # False
```

`has-attribute` reports whether a name is a real column on the schema (not
whether a value has been assigned).

```perl6
$user.has-attribute('fname');   # True
$user.has-attribute('bogus');   # False
```

`attribute-names` returns the list of schema columns, and `attributes`
returns a hash dump of the current attribute values. The dump is a clone, so
mutating it does not affect the record.

```perl6
$user.attribute-names;   # (id fname lname created_at updated_at)
my %dump = $user.attributes;
%dump<fname> = 'X';      # does not touch the live record
```

## State Predicates

A record reports its lifecycle stage through a small set of predicates.

```perl6
my $user = User.build({fname => 'Greg'});
$user.is-new-record;     # True
$user.is-persisted;      # False
$user.is-destroyed;      # False

$user.save;
$user.is-new-record;     # False
$user.is-persisted;      # True

$user.destroy;
$user.is-persisted;      # False
$user.is-destroyed;      # True
$user.is-frozen;         # True
```

The `was-*` predicates report on the previous transition. `was-new-record`
flips to `True` after the first successful `save`, then back to `False` on
the next save (because the next save is an update, not an insert).
`was-persisted` flips to `True` after a persisted record is destroyed.

```perl6
my $user = User.build({fname => 'Greg'});
$user.was-new-record;      # False

$user.save;
$user.was-new-record;      # True  -- just got created

$user.fname = 'G2';
$user.save;
$user.was-new-record;      # False -- the last save was an update

$user.destroy;
$user.was-persisted;       # True
```

After `destroy`, the record is frozen: any write path raises
`X::FrozenRecord`. Reads continue to work.

```perl6
use ORM::ActiveRecord::Errors::X;

my $user = User.create({fname => 'Greg'});
$user.destroy;

try {
  $user.write-attribute('fname', 'Bob');
  CATCH {
    when X::FrozenRecord { say 'cannot write to a destroyed record' }
  }
}

$user.read-attribute('fname');   # 'Greg' -- reads still work
```

## Dirty Tracking

The dirty tracking surface mirrors Rails. A record exposes both what is
changed *right now* (since the last load or save) and what was changed
*previously* (the diff that the last save persisted).

### Current changes

```perl6
my $user = User.create({fname => 'Greg', lname => 'Donald'});
$user.is-changed;            # False

$user.fname = 'Bob';
$user.is-changed;            # True
$user.changed;               # (fname)
$user.changes;               # {fname => ['Greg', 'Bob']}
$user.changed-attributes;    # {fname => 'Greg'}
```

Per-attribute predicates exist in two forms: an explicit one that takes the
attribute name, and a dynamic dispatch that builds the method name from it.

```perl6
$user.is-attribute-changed('fname');   # True
$user.attribute-was('fname');          # 'Greg'
$user.attribute-change('fname');       # ['Greg', 'Bob']

# Same thing via dynamic dispatch
$user.is-fname-changed;                # True
$user.fname-was;                       # 'Greg'
$user.fname-change;                    # ['Greg', 'Bob']
```

`attribute-will-change` forces an attribute to be considered dirty even
when its value did not change. The dynamic form is `<attr>-will-change`.

```perl6
$user.attribute-will-change('fname');  # or $user.fname-will-change;
$user.is-changed;                      # True
```

### Previous changes (after save)

`save` flushes the current changes into `previous-changes`, then resets the
in-memory dirty state.

```perl6
my $user = User.create({fname => 'Greg'});
$user.fname = 'Bob';
$user.save;

$user.is-changed;                      # False -- save flushed the diff
$user.previous-changes;                # {fname => ['Greg', 'Bob']}
$user.is-saved-change-to('fname');     # True
$user.saved-change-to('fname');        # ['Greg', 'Bob']
$user.attribute-before-last-save('fname');  # 'Greg'

# Dynamic forms
$user.is-saved-change-to-fname;        # True
$user.saved-change-to-fname;           # ['Greg', 'Bob']
$user.fname-before-last-save;          # 'Greg'
```

### Restoring & reloading

`restore-attributes` reverts every in-memory change back to the last saved
value. `restore-<attr>` (or `reset-<attr>`) reverts a single attribute.

```perl6
my $user = User.create({fname => 'Greg', lname => 'Donald'});
$user.fname = 'Bob';
$user.lname = 'B';
$user.restore-attributes;
$user.fname;                 # 'Greg'
$user.lname;                 # 'Donald'

$user.fname = 'Bob';
$user.restore-fname;         # or $user.reset-fname;
$user.fname;                 # 'Greg'
```

`reload` re-fetches every column from the database and clears any dirty
state. Use it when another process may have updated the same row.

```perl6
$user.reload;
$user.is-changed;            # False
```

## Targeted Writes

Sometimes a full `save` is heavier than the task at hand. The targeted-write
helpers give you finer control over which steps run.

| Method | Validations | Callbacks | Timestamps | Persists |
|--------|-------------|-----------|------------|----------|
| `save` / `update`                  | yes | yes | yes | yes |
| `update-attribute(name, val)`      | no  | yes | yes | yes |
| `update-column(name, val)`         | no  | no  | no  | yes |
| `update-columns(%attrs)`           | no  | no  | no  | yes |
| `touch(*@names)`                   | no  | no  | yes | yes |
| `increment(name, n=1)`             | -   | -   | -   | no  |
| `increment-or-die(name, n=1)`      | no  | yes | yes | yes |
| `decrement(name, n=1)`             | -   | -   | -   | no  |
| `decrement-or-die(name, n=1)`      | no  | yes | yes | yes |
| `toggle(name)`                     | -   | -   | -   | no  |
| `toggle-or-die(name)`              | no  | yes | yes | yes |

### update-column / update-columns

Skip everything (validations, callbacks, timestamps) and persist exactly
what you ask for. Useful for low-level fixes or background workers that
must not trigger user-visible side effects.

```perl6
$user.update-column('fname', 'Greg');
$user.update-columns({fname => 'Greg', lname => 'Donald'});
```

### update-attribute

Runs callbacks and bumps timestamps but skips validations. Use it when you
need a single attribute persisted regardless of whether the rest of the
record is currently valid.

```perl6
$user.update-attribute('lname', '');     # saves even though presence-required
```

### touch

`touch` bumps `updated_at` (and any extra columns you name) without
modifying anything else.

```perl6
$user.touch;
$user.touch('last_seen_at', 'last_login_at');
```

`touch-all` is the relation-level form: it touches every matching row.

```perl6
User.where({role => 'admin'}).touch-all;
```

### increment / decrement / toggle

The unsuffixed forms mutate the in-memory value and leave persistence to
you. The `-or-die` variants persist via `update-attribute` (so callbacks and
timestamps run, validations do not) and raise `X::RecordInvalid` on failure.

```perl6
$post.increment('views');           # in memory
$post.increment-or-die('views');    # persisted, +1

$cart.decrement('item_count', 2);
$user.toggle('active');
$user.toggle-or-die('active');
```

## Bulk Operations

When you need to write many rows in one round-trip — or to skip the
validation/callback pipeline entirely — reach for the bulk helpers. They
operate on the database directly and return affected row counts (or
generated ids), not model instances.

### update-all / delete-all

`update-all` issues a single `UPDATE` against the rows the relation
matches. It returns the number of affected rows. Validations and
callbacks are skipped; no timestamps are bumped automatically.

```perl6
User.where({role => 'guest'}).update-all(role => 'member');
User.update-all(active => True);
```

`delete-all` issues a single set-based `DELETE` and returns the count of
removed rows. No `before-destroy` / `after-destroy` callbacks fire.

```perl6
User.where({inactive_since => Date.new('2020-01-01') ..}).delete-all;
```

`destroy-by(%conditions)` and `delete-by(%conditions)` are class-level
shortcuts. `destroy-by` walks the matching records and runs callbacks;
`delete-by` is the fast set-based form.

```perl6
User.destroy-by({banned => True});   # runs before/after-destroy callbacks
User.delete-by({banned => True});    # single SQL DELETE
```

### Model.update(@ids, %attrs)

Updates several records by primary key. Each id is loaded, mutated, and
saved through the regular `update` path — validations and callbacks run
for every record.

```perl6
User.update([1, 2, 3], {role => 'member'});

# Per-id attrs:
User.update([1, 2], [
  {fname => 'Alice'},
  {fname => 'Bob'},
]);
```

### update-counters

Atomic counter increments / decrements expressed in a single SQL
statement. Callbacks do not fire and timestamps are not bumped.

```perl6
Post.update-counters($post.id, views => 1);
Post.update-counters([1, 2, 3], votes => 5, comments_count => -1);

Post.where({published => True}).update-counters(views => 1);
```

### insert / insert-all

`insert` writes a single row, skipping validations and callbacks. If a
unique constraint would be violated, the row is silently skipped (returns
`0`). `insert-or-die` lets the database error propagate.

```perl6
my $id = User.insert({fname => 'Greg', lname => 'Donald'});

User.insert-or-die({fname => 'Greg'});      # raises on duplicate
```

`insert-all(@rows)` writes many rows in a single statement. It returns
the list of inserted ids. The `-or-die` variant raises on any conflict.

```perl6
my @ids = User.insert-all([
  {fname => 'Greg',  lname => 'Donald'},
  {fname => 'Alice', lname => 'Smith'},
]);
```

Both forms auto-populate `created_at` / `updated_at` if those columns
exist and are not supplied.

### upsert / upsert-all

`upsert` does an `INSERT … ON CONFLICT … DO UPDATE`. By default it
conflicts on the primary key; pass `:unique-by` to target a different
unique constraint. Pass `:update-cols` to limit which columns are
overwritten on conflict (otherwise every supplied column is overwritten).

```perl6
# Update by id if present; otherwise insert.
User.upsert({id => 42, fname => 'Greg', lname => 'Donald'});

# Insert a new row, or update on name collision.
User.upsert(
  {fname => 'Greg', email => 'greg@example.com'},
  unique-by => <email>,
);
```

`upsert-all` is the bulk form. It returns the number of affected rows
(inserts plus updates).

```perl6
User.upsert-all(
  [
    {email => 'a@example.com', fname => 'Alice'},
    {email => 'b@example.com', fname => 'Bob'},
  ],
  unique-by => <email>,
);
```

## Save Options

`save` accepts two opt-out flags:

- `:!validate` — bypass validations.
- `:!touch` — skip the automatic `created_at` / `updated_at` bump.

```perl6
$user.save(:!validate);     # persist even if invalid
$user.save(:!touch);        # do not bump the timestamps
```

## Readonly Records

`make-readonly` marks a record as read-only. Subsequent `save`, `update`, or
`delete` calls raise `X::ReadOnlyRecord`. `is-readonly` reports the flag.

```perl6
my $user = User.create({fname => 'Greg'});
$user.make-readonly;
$user.is-readonly;       # True

try {
  $user.save;
  CATCH {
    when X::ReadOnlyRecord { say 'cannot save a readonly record' }
  }
}
```

## Automatic Timestamps

If a table has `created_at` and/or `updated_at` columns, ORM::ActiveRecord
manages them for you. `created_at` is set on insert; `updated_at` is set on
every save (insert and update).

See [Migrations &raquo; Timestamps](../migrations.md#timestamps) for the
column setup.
