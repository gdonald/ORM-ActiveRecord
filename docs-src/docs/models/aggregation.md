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

## group and having

`group(*@cols)` adds `GROUP BY`. `having($predicate, *@binds)` adds a
`HAVING` clause; binds are parameterised.

```perl6
User.group('lname').count;                                    # 1 row per lname
User.group('lname').having('count(*) > 1').pluck('lname');
User.group('lname').having('count(*) > ?', 1).count;
```

`regroup(*@cols)` replaces any prior `group` clause. `unscope(:group)` and
`unscope(:having)` drop the respective clause.

```perl6
User.group('lname').regroup('fname');           # only fname grouping remains
User.group('lname').unscope(:group).all;        # plain SELECT
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
