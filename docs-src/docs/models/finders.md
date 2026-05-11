# Finders

ORM::ActiveRecord provides a range of class-level finder methods for locating
records.

## find

`find($id)` looks up a record by primary key. It raises `X::RecordNotFound`
if no row matches.

```perl6
use ORM::ActiveRecord::X;

my $user = User.find(42);

try {
  User.find(99_999);

  CATCH {
    when X::RecordNotFound {
      say .message;   # Couldn't find User with id=99999
    }
  }
}
```

## find-by

`find-by(%conditions)` returns the first matching record, or `Nil` if there is
no match.

```perl6
my $user = User.find-by({fname => 'Greg'});
if $user.defined {
  say $user.lname;
}
```

`find-by-or-die(%conditions)` raises `X::RecordNotFound` instead of returning
`Nil`.

```perl6
my $user = User.find-by-or-die({fname => 'Greg'});
```

## first / last / take

`first` and `last` return a single record ordered by `id`. `take` returns up
to N records with no order guarantee.

```perl6
User.where({active => True}).first;   # ORDER BY id LIMIT 1
User.where({active => True}).last;    # ORDER BY id DESC LIMIT 1

User.take;        # one record (LIMIT 1)
User.take(5);     # up to five records
```

When you need a different order, chain `.order` before `.first` / `.last`:

```perl6
User.order('lname').first;
```

### first(N) / last(N)

Pass an integer to get back an array of up to N records.

```perl6
User.first(3);                       # first three by id ASC
User.last(3);                        # last three rows, returned in id ASC

User.where({active => True}).first(2);
User.order('fname').last(2);         # reverses the order, returns trailing
                                     # rows in the original direction
```

`first(0)` and `last(0)` return an empty list.

## sole / find-sole-by

`sole` returns the single record matched by a relation. Raises
`X::RecordNotFound` if there are zero matches, or `X::SoleRecordExceeded`
if there are two or more.

```perl6
use ORM::ActiveRecord::Errors::X;

my $admin = User.where({role => 'admin'}).sole;     # exactly one or raise
```

`find-sole-by(%conditions)` is the class-level shorthand:

```perl6
my $row = User.find-sole-by({email => 'greg@example.com'});
```

## find-or-create-by / find-or-initialize-by

`find-or-create-by(%attrs)` returns the first row matching `%attrs`, or
creates one with those attributes if no row matches. The returned record may
be invalid if creation failed validation — `is-invalid` is `True` and
`errors` is populated.

```perl6
my $u = User.find-or-create-by({email => 'greg@example.com'});
if $u.is-invalid {
  say $u.errors.full-messages;
}
```

`find-or-create-by-or-die(%attrs)` raises `X::RecordInvalid` instead of
returning an invalid record.

`find-or-initialize-by(%attrs)` is the no-save variant: returns the existing
record if found, or builds an unsaved record otherwise.

```perl6
my $u = User.find-or-initialize-by({email => 'new@example.com'});
$u.fname = 'Greg';
$u.save;
```

When called on a relation, prior `where` conditions are merged into the
create attributes:

```perl6
User.where({role => 'admin'}).find-or-create-by({email => 'a@example.com'});
# WHERE role='admin' AND email='a@example.com'
# If missing: creates with role='admin', email='a@example.com'
```

## create-with

`create-with(%attrs)` attaches default attributes to a relation. They flow
into a record created via `find-or-create-by` / `find-or-initialize-by`, but
are not used as `where` conditions for the find step.

```perl6
User.create-with({role => 'admin'}).find-or-create-by({email => 'a@example.com'});
# Find ignores `role`; if created, the new row has role='admin' as well.
```

Find-step parameters always win over `create-with` defaults if a key
overlaps.

## pick

`pick(*@cols)` returns a single row's values without instantiating a model.
For one column, it returns the scalar value. For multiple columns, it
returns an array. Returns `Any` when no row matches.

```perl6
my $fname = User.order('id').pick('fname');
my $row   = User.order('id').pick('fname', 'lname');   # ['Alice', 'Anderson']

my $none  = User.where({fname => 'Zelda'}).pick('fname');   # Any
```

## exists

`exists` returns `True` if any row matches.

```perl6
User.exists;                       # True if the table has any rows
User.exists({fname => 'Greg'});    # True if at least one match
```
