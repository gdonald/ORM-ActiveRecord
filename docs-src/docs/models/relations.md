# Relations

`User.where(...)`, `User.order(...)`, and friends return a chainable relation
that defers running SQL until you ask for results. Realise the relation by
calling `.all`, `.first`, `.last`, `.count`, `.pluck`, `.ids`, or `.exists`.

```perl6
my @recent = User
  .where({active => True})
  .order('created_at DESC')
  .limit(10)
  .all;
```

## where

`where(%conditions)` adds equality conditions joined with `AND`. Conditions
are bound as parameters, never interpolated, so user-supplied values are safe.

```perl6
User.where({active => True, fname => 'Greg'});
```

You can chain further `.where(...)` calls to merge in additional conditions.

```perl6
my $q = User.where({active => True});
$q = $q.where({fname => 'Greg'}) if $only-greg;
my @users = $q.all;
```

## order

`order(*@cols)` adds `ORDER BY` clauses. Pass column names or fully formed
fragments like `'fname DESC'`.

```perl6
User.order('lname');
User.order('lname', 'fname');
User.order('created_at DESC');
```

## limit and offset

`limit(N)` and `offset(N)` add `LIMIT` and `OFFSET`. Useful for pagination.

```perl6
sub page-of-users(Int :$page = 1, Int :$per = 20) {
  User.order('id').limit($per).offset(($page - 1) * $per).all;
}
```

## all

`Model.all` returns a relation that, once realised, returns every row. You can
chain conditions onto it just like `where`.

```perl6
User.all.where({active => True}).order('lname').all;
```

## pluck and ids

`pluck` returns raw column values without instantiating model objects. It is
much cheaper than materialising records and dropping everything but one
column.

```perl6
my @fnames = User.pluck('fname');
# (Alice Bob Carol Dave Eve)

my @rows = User.order('id').pluck('fname', 'lname');
# ((Alice Anderson) (Bob Brown) ...)
```

`ids` is the common shorthand for `pluck('id')`.

```perl6
my @ids = User.where({active => True}).ids;
```

## count and exists

`count` returns the number of matching rows. `exists` returns `True` if any
row matches.

```perl6
User.where({active => True}).count;
User.where({active => True}).exists;
```
