# Raw SQL and CTEs

When the chainable relation DSL is not enough, ORM::ActiveRecord exposes a
handful of escape hatches that let you reach for raw SQL or Common Table
Expressions while still getting model instances back.

## find-by-sql

`find-by-sql(...)` runs an arbitrary SELECT and returns an array of model
instances. The columns of the result set are mapped onto the model's attrs,
so any column the model already knows about is coerced through its declared
type; extra columns are passed through as raw values.

The variadic form takes a SQL string with `?` placeholders and the bind
values inline:

```perl6
my @users = User.find-by-sql('SELECT * FROM users WHERE fname = ?', 'Bob');
```

The array form is identical to `sanitize-sql-array`: positional `?` binds or
`:name` binds with a trailing hash.

```perl6
User.find-by-sql(['SELECT * FROM users WHERE fname = ?',  'Bob']);
User.find-by-sql(['SELECT * FROM users WHERE fname = :n', { n => 'Bob' }]);
```

## select-all

`select-all(...)` runs a SELECT and returns the rows as plain hashes (no
model instantiation). Same calling conventions as `find-by-sql`:

```perl6
my @rows = User.select-all('SELECT fname, count(*) AS n FROM users GROUP BY fname');
say @rows[0]<n>;     # 3
```

Useful for reports or any query whose columns don't line up with the model.

## with

`with(%name-to-sub-query)` adds Common Table Expressions to the outer
relation. Each value may be either another `Query` (a relation) or a raw SQL
string:

```perl6
my $heavy = User.where({fname => 'Greg'});
User.with(matches => $heavy).where({lname => 'Donald'}).all;

User.with(top => 'SELECT * FROM users ORDER BY id LIMIT 10').all;
```

When the CTE has the same name as the model's table, the outer SELECT reads
from the CTE instead of the table. To reference a CTE under a different
name, use `.from('cte_name', 'qualifier_alias')` so the SELECT list still
qualifies columns correctly:

```perl6
User.with(top => User.order('id').limit(10))
    .from('top', 'users')
    .all;
```

The sub-query's bind values are inserted into the outer statement ahead of
the outer query's binds — placeholder numbering is handled automatically,
including under PostgreSQL's `$N` bind syntax.

## with-recursive

`with-recursive(%name-to-sub-query)` emits `WITH RECURSIVE ...`. Recursive
CTEs typically reference their own name inside the sub-query, so a raw SQL
string is the natural form:

```perl6
my @ints = User.with-recursive(nums => q:to/SUB/).from('nums').pluck('nums.n');
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM nums WHERE n < 10
  SUB
```

## annotate

`annotate("comment")` attaches an SQL comment to the emitted query. Useful
for tagging queries in logs and APM tooling so you can trace a slow query
back to the call site that produced it.

```perl6
User.annotate('reports#monthly').where({active => True}).all;
# SELECT ... FROM users WHERE active = $1 /* reports#monthly */
```

Multiple annotations stack in declaration order. Embedded `*/` is
neutralised so a comment can't terminate the block prematurely.

```perl6
User.annotate('first').annotate('second').all;
# ... /* first */ /* second */
```

## optimizer-hints

`optimizer-hints("...")` emits a `/*+ ... */` block immediately after the
`SELECT` keyword, where MySQL (and Postgres with `pg_hint_plan`) look for
planner directives.

```perl6
User.optimizer-hints('NO_INDEX_MERGE(users)').all;
# SELECT /*+ NO_INDEX_MERGE(users) */ users.id, ... FROM users

User.optimizer-hints('MAX_EXECUTION_TIME(1000)', 'NO_ICP(users)').all;
# SELECT /*+ MAX_EXECUTION_TIME(1000) NO_ICP(users) */ ...
```

Multiple hints share one `/*+ ... */` block. Engines that don't understand
the hint syntax treat it as an ordinary comment, so the query still runs.

## to-sql

`to-sql` returns the SQL string that the relation would execute, with
adapter-specific placeholders (`$N` for PostgreSQL, `?` for SQLite and
MySQL) left in. Bind values are not inlined.

```perl6
say User.where({active => True}).annotate('debug').to-sql;
```
