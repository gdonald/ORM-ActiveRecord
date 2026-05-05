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

## exists

`exists` returns `True` if any row matches.

```perl6
User.exists;                       # True if the table has any rows
User.exists({fname => 'Greg'});    # True if at least one match
```
