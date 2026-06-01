# Queries

This page covers the filtering and relation-modification vocabulary that
builds on the basics in [Relations](relations.md). Everything here returns
a new relation — the original is never mutated.

## where shorthands

`where(%conditions)` accepts several value shapes:

| Shape                          | SQL emitted                          |
| ------------------------------ | ------------------------------------ |
| `where({col => $value})`       | `col = ?`                            |
| `where({col => Nil})`          | `col IS NULL`                        |
| `where({col => [a, b, c]})`    | `col IN (?, ?, ?)`                   |
| `where({col => 1..10})`        | `col BETWEEN ? AND ?`                |
| `where({assoc => $instance})`  | `assoc_id = ?` (uses `$instance.id`) |

```perl6
User.where({age => 18..65});
User.where({email => Nil});
User.where({id => [1, 2, 3]});
User.where({user => $alice});            # belongs_to :user
```

## where.not

`where.not(%conditions)` adds a negated condition. `Nil`, ranges, and arrays
work the same as the positive form.

```perl6
User.where.not({fname => 'Bob'}).count;
User.where.not({email => Nil}).all;          # IS NOT NULL
User.where.not({age => 18..65}).all;         # NOT BETWEEN
User.where.not({id => [1, 2, 3]}).all;       # NOT IN (...)
```

## where.missing and where.associated

For relations through associations, `where.missing(:assoc)` finds records
with no associated rows; `where.associated(:assoc)` finds those that have at
least one. Both work over `belongs_to`, `has_many`, and `has_many :through`.

```perl6
User.where.missing(:subscriptions).all;       # users with no subscription
User.where.associated(:subscriptions).all;    # users with at least one
User.where.missing(:magazines).all;           # honors :through
```

`Model.associated(:assoc)` is a class-level shortcut for the common case.

## excluding

`excluding(*@records-or-ids)` removes specific rows from the result set,
mirroring `WHERE id NOT IN (...)`.

```perl6
User.excluding($bob).all;                          # by instance
User.excluding($alice, $dave).all;                 # multiple
User.excluding(1, 2, 3).all;                       # by id
```

It composes:

```perl6
User.where({lname => 'Anderson'}).excluding($alice).all;
```

## or and and

`or(other_relation)` and `and(other_relation)` combine WHERE clauses across
two relations. The result is a single SQL query with the conditions wrapped
in the right boolean structure.

```perl6
User.where({fname => 'Alice'}).or(User.where.not({fname => 'Carol'})).all;
User.where({active => True}).and(User.where({verified => True})).all;
```

## merge

`merge(other_relation)` folds another relation's clauses into this one.
Last-wins semantics: `other` takes precedence for `limit`, `offset`,
`distinct`, and `readonly`. `where`, `order`, `joins`, and similar additive
clauses are concatenated.

```perl6
my $base   = User.where({active => True});
my $sorted = User.order('lname');
my @rows   = $base.merge($sorted).all;

# Override pagination from another relation
User.limit(10).merge(User.limit(2)).all;     # uses LIMIT 2
```

## rewhere

`rewhere(%conditions)` replaces any prior `where` conditions on the same
columns. Useful when narrowing-then-broadening.

```perl6
my $q = User.where({active => True, role => 'admin'});
$q.rewhere({role => 'superadmin'}).all;     # active=True still, role swapped
```

## unscope

`unscope(:scope)` surgically removes a single relation dimension:

```perl6
User.where({active => True}).unscope(:where).all;   # drop all WHERE
User.order('lname').unscope(:order).all;             # drop ORDER BY
User.group('lname').unscope(:group).all;             # drop GROUP BY
User.distinct.unscope(:distinct).all;                # drop DISTINCT
```

You can also drop a single `where` condition by column:

```perl6
User.where({active => True, role => 'admin'})
    .unscope(where => :role)
    .all;
```
