# Relations

`User.where(...)`, `User.order(...)`, and friends return a chainable relation
that defers running SQL until you ask for results. Relations compose: every
scope-narrowing call returns a new relation, leaving the original untouched.

```perl6
my $active = User.where({active => True});
my $recent = $active.order('created_at DESC').limit(10);

# $active and $recent are independent relations; neither has hit the DB yet.
my @rows = $recent.all;   # one query, fired here
```

## Realising a relation

Relations stay lazy until you call one of these methods:

| Method        | Returns                                    |
| ------------- | ------------------------------------------ |
| `.all`        | List of model instances                    |
| `.first`      | One instance ordered by `id` ASC, or `Nil` |
| `.last`       | One instance ordered by `id` DESC, or `Nil`|
| `.count`      | `Int` — `COUNT(*)`                         |
| `.exists`     | `Bool`                                     |
| `.pluck(...)` | List of raw column values                  |
| `.ids`        | List of `id` column values (= `pluck('id')`) |

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

`where` accepts several value shorthands beyond a literal scalar:

```perl6
User.where({age   => 18..65});           # BETWEEN
User.where({email => Nil});              # IS NULL
User.where({id    => [1, 2, 3]});        # IN
User.where({user  => $alice});           # auto-uses $alice.id as user_id
```

See [Queries](queries.md) for the full filtering vocabulary, including
`where.not`, `where.missing`, `where.associated`, `or`, `and`, `merge`,
`rewhere`, `unscope`, and `excluding`.

## order

`order(*@cols)` adds `ORDER BY` clauses. Pass column names or fully formed
fragments like `'fname DESC'`.

```perl6
User.order('lname');
User.order('lname', 'fname');
User.order('created_at DESC');
```

`reorder(...)` replaces any prior `order` clauses. `in-order-of(:col, [...])`
orders rows to match an explicit value list.

```perl6
User.order('lname').reorder('id');                       # only 'id' is applied
User.in-order-of(:id, [3, 1, 2]).all;                    # rows in [3, 1, 2] order
```

## limit and offset

`limit(N)` and `offset(N)` add `LIMIT` and `OFFSET`. Useful for pagination.

```perl6
sub page-of-users(Int :$page = 1, Int :$per = 20) {
  User.order('id').limit($per).offset(($page - 1) * $per).all;
}
```

SQLite and MySQL require a `LIMIT` whenever an `OFFSET` is set; the adapter
adds a synthetic unbounded `LIMIT` when you pass `offset` alone.

## all

`Model.all` returns a relation that, once realised, returns every row. You can
chain conditions onto it just like `where`.

```perl6
User.all.where({active => True}).order('lname').all;
```

## none

`Model.none` returns a chainable null relation. Every operation that would
hit the database returns the empty result for its return type (`[]`, `0`,
`False`, `Nil`, …) without issuing SQL. Useful as a "no match" return value
from helper methods that must still hand back a chainable relation.

```perl6
sub recent-for($user) {
  return User.none unless $user.defined && $user.active;
  User.where({author_id => $user.id}).order('created_at DESC');
}

recent-for(Nil).count;     # 0, no query issued
recent-for(Nil).all;       # ()
```

`none` is sticky once set; further `where`, `order`, etc. compose but the
result stays empty. `merge(other.none)` propagates the null relation.

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
