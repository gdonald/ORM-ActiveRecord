# Aggregation and Selection

Beyond filtering, relations expose set-shaping operations: deduplication,
grouping, subquery sources, and per-relation flags.

## distinct

`distinct` adds `SELECT DISTINCT`. Applies across all selected columns.

```perl6
User.distinct.count;                        # = total user count
User.select('lname').distinct.pluck('lname');
User.select('lname').distinct.count;        # = number of unique lnames
```

`distinct(False)` clears the flag again. `unscope(:distinct)` does the same.

```perl6
User.select('lname').distinct.distinct(False).pluck('lname');
User.distinct.unscope(:distinct);
```

## sum, average, minimum, maximum

These return a scalar across the relation. NULLs are ignored; `sum` on an
empty relation returns `0`, and the others return `Nil`.

```perl6
Game.sum('year');                              # 7503
Game.minimum('year');                          # 1500
Game.maximum('year');                          # 2200
Game.average('year');                          # mean as Numeric

Game.where({name => 'Chess'}).sum('year');     # honors WHERE
Game.none.sum('year');                         # 0
Game.none.maximum('year');                     # Nil
```

When the relation has `joins`, bare column names are auto-qualified with the
base table. Pass `"games.year"` or any other qualified form explicitly to
override.

## calculate

`calculate($op, $col?)` dispatches to the right aggregate by name. `$op` is
case-insensitive and accepts `sum`, `avg`/`average`, `min`/`minimum`,
`max`/`maximum`, and `count`. `count` is the only operation where `$col` is
optional.

```perl6
Game.calculate('sum',     'year');             # = Game.sum('year')
Game.calculate('average', 'year');             # = Game.average('year')
Game.calculate('count');                       # = Game.count
Game.where({name => 'Chess'}).calculate('max', 'year');
```

## count

`count` returns an `Int` for an ungrouped relation. With a column, it
counts non-NULL rows; combined with `distinct`, it counts distinct
non-NULLs.

```perl6
Game.count;                                    # all rows
Game.count('year');                            # rows where year IS NOT NULL
Game.distinct.count('name');                   # COUNT(DISTINCT name)
```

For a grouped relation, see below.

## group and having

`group(*@cols)` adds `GROUP BY`. `having(...)` adds a `HAVING` clause. The
raw form accepts a SQL fragment with positional binds; the hash form is
Rails-style and works on aggregates or grouped columns.

```perl6
# Hash of group value => count (Rails-aligned)
User.group('lname').count;
# { Anderson => 2, Brown => 1, Carter => 1 }

# Filter groups: raw fragment, parameterised
User.group('lname').having('count(*) > ?', 1).count;       # { Anderson => 2 }

# Filter groups: hash form using an aggregate expression as the key
User.group('lname').having({ 'count(*)' => 2..* }).count;  # { Anderson => 2 }
```

Other aggregates on a grouped relation return a hash keyed by the group
value:

```perl6
Game.group('name').sum('year');
# { Chess => 3200, Go => 2200, Poker => 1810, Magic => 1993 }

Game.group('name').maximum('year');            # per-group max
Game.group('name').minimum('year');            # per-group min
Game.group('name').average('year');            # per-group mean
```

`regroup(*@cols)` replaces any prior `group` clause. `unscope(:group)` and
`unscope(:having)` drop the respective clause.

```perl6
User.group('lname').regroup('fname');           # only fname grouping remains
User.group('lname').unscope(:group).all;        # plain SELECT
```

## pluck of SQL expressions

`pluck` accepts a bare column name or an arbitrary SQL expression. An entry
is treated as an expression (no auto-qualification) when it contains a
parenthesis, a dot, or whitespace.

```perl6
Game.pluck('UPPER(name)');                     # ['CHESS', 'GO', ...]
Game.pluck('games.year');                      # already qualified
Game.pluck('LOWER(name)', 'year');             # multi-column
```

## from

`from($source [, $alias])` replaces the implicit `FROM table_name`. Use it
for subqueries or aliased base tables.

```perl6
User.from('users').count;
User.from('(SELECT * FROM users WHERE lname != ?) users', 'Brown').all;

my $q = User.from('users AS u', 'u');
$q.from-alias;                                    # 'u'
$q.from-source;                                   # 'users AS u'
```

`unscope(:from)` resets to the default table.

## readonly

A `readonly` relation produces records that refuse to `save` / `update` /
`destroy`. Useful when a query crosses join tables and the records should not
be persisted back.

```perl6
my @users    = User.readonly.all;          # @users[0].save throws
my @writable = User.readonly.unscope(:readonly).all;
```

`merge` propagates the flag:

```perl6
User.all.merge(User.readonly).readonly-value;     # True
```

## extending

`extending(*@modules)` mixes additional methods into the relation. Useful
for paginators or custom finders local to a query chain.

```perl6
role Pagination {
  method page(Int $n, Int :$per = 25) {
    self.limit($per).offset(($n - 1) * $per);
  }
}

my @page1 = User.order('id').extending(Pagination).page(1).all;
my @page2 = User.order('id').extending(Pagination).page(2).all;
```

You can pass multiple modules; their methods compose in declaration order.

```perl6
role NameOnly {
  method names { self.pluck('fname') }
}

User.order('id').extending(Pagination, NameOnly).page(1).names;
```
