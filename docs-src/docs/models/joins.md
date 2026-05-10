# Joins

`joins` and `left-outer-joins` add SQL `JOIN` clauses to a relation. They
accept several forms:

## By association name

Pass an association name (defined via `has-many` / `belongs-to`):

```perl6
Subscription.joins('user').count;            # belongs_to side
User.joins(:subscriptions).count;            # has_many side
User.joins(:magazines).count;                # has_many :through
```

The join condition (`subscriptions.user_id = users.id`, etc.) is derived from
the association definition.

## Nested associations

A nested-hash form follows multi-level associations:

```perl6
User.joins(:subscriptions(:magazine)).count;
```

This emits a join through `subscriptions` then `magazines`.

## Raw SQL

For one-offs that don't map to an association, pass a literal join clause:

```perl6
my $raw = 'INNER JOIN subscriptions ON subscriptions.user_id = users.id';
User.joins($raw).count;
```

## left-outer-joins

`left-outer-joins` keeps rows from the base table even when no related row
exists. Useful for "find users with or without subscriptions".

```perl6
User.left-outer-joins(:subscriptions).count;            # all users
User.left-outer-joins(:subscriptions).distinct.count;   # all users, deduped
```

## Filtering on a joined table

Once you've joined, `where` accepts a nested hash to filter on the joined
table's columns.

```perl6
Subscription.joins(:user).where({users => {fname => 'Alice'}}).all;
User.joins(:subscriptions(:magazine))
    .where({magazines => {title => 'Mad'}})
    .distinct
    .all;
```

A bare column name in `where` after a join still resolves to the base table:

```perl6
User.joins(:subscriptions).where({fname => 'Alice'}).distinct.count;
# WHERE users.fname = 'Alice'
```

## references

`references(*@table-names)` is a hint that named tables will be filtered or
ordered against. It pre-declares the join targets without altering row counts
itself, which matters when combining with eager loading (where the difference
between `preload` and `eager_load` depends on whether you reference the
joined table elsewhere).

```perl6
User.references('posts').count;
User.references('posts', 'comments');
```

## distinct under joins

A `joins` on a `has_many` returns one row per join row, so deduping with
`distinct` is common when counting base records.

```perl6
User.joins(:subscriptions).count;             # = total subscription count
User.joins(:subscriptions).distinct.count;    # = users with >= 1 subscription
```
