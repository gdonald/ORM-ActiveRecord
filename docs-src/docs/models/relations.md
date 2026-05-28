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

## preload, eager-load, includes

These three modifiers eliminate the N+1 query problem by loading associations
up front and caching them on each parent record.

`preload(...)` runs one extra query per named association after fetching the
parent rows. It is the right default when you only need to read the children
back through the accessor.

```perl6
my @users = User.where({}).preload(:pages).all;
for @users -> $u {
  say $u.pages.elems;     # no extra DB query — pages came from the cache
}
```

`eager-load(...)` does the same caching but also adds a LEFT OUTER JOIN to the
parent query. Use this when you need to filter on a joined column:

```perl6
User.where({}).eager-load(:profile).where({'profiles.is_active' => True}).all;
```

`includes(...)` behaves like `preload` by default. It promotes itself to
`eager-load` when something later in the chain proves a JOIN is required:

- An explicit `references(:assoc)` — order of the two calls doesn't matter.
- A `where`/`order`/`having` fragment that mentions a column on the joined
  table, in any of the supported forms.

```perl6
# all four chains end up doing the same SELECT … LEFT OUTER JOIN profiles …
User.includes(:profile).references(:profile);
User.references(:profile).includes(:profile);
User.includes(:profile).where({'profiles.is_active' => True});
User.includes(:profile).where(profiles => { is_active => True });
User.includes(:profile).all;                       # plain preload — no JOIN
```

`references` takes the colon-pair form `references(:profile)` or the
arrow-pair form `references(profile => True)`; a falsy value
(`references(profile => False)`) is ignored, so it adds nothing and does not
promote `includes`.

`preload(:assoc)` and `eager-load(:assoc)` are explicit and never get
re-routed: a chain like `preload(:profile).references(:profile)` stays a
preload, and `eager-load(:profile)` stays a JOIN even with no `references`.

Both forms Rails uses for nested includes are supported, and the three
loaders (`preload`, `eager-load`, `includes`) accept the same shapes.

Array form — multiple top-level associations:

```perl6
User.where({}).preload(:pages, :profile).all;
User.where({}).includes(:pages, :profile).all;
```

Hash form (Raku `Pair`) — load a child association on top of its parent:

```perl6
User.where({}).preload(articles => :scribe).all;
User.where({}).includes(articles => :scribe).all;
```

The two forms compose, including for arbitrary depth. The value side of a
`Pair` can itself be another `Pair`, a `Hash`, or a list:

```perl6
# users → articles → scribe → pages
User.where({}).preload(articles => { scribe => :pages }).all;

# users → pages (no nested) AND users → articles → scribe
User.where({}).preload(:pages, articles => :scribe).all;
```

Each loaded record exposes its cache as `record.assoc-cache<name>`, so tests
and instrumentation can verify what was preloaded without re-querying.

### Polymorphic associations

`preload` and `includes` both batch polymorphic associations by type:

```perl6
class Attachment is Model {
  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
  }
}

# One query for attachments, plus one query per distinct attachable_type.
my @atts = Attachment.where({}).preload(:attachable).all;
```

`eager-load(:polymorphic-assoc)` raises an error — the target table varies
per row, so a single LEFT OUTER JOIN cannot resolve it. Use `preload` (or
`includes` without a JOIN-forcing chain) instead.

The polymorphic *inverse* (`has_many :as`) is loaded with a single query
scoped by `<as>_id` and `<as>_type`:

```perl6
class User is Model {
  submethod BUILD {
    self.has-many: pictures => %(class => Picture, as => 'imageable');
  }
}

# One query for users, one query for matching pictures.
my @users = User.where({}).preload(:pictures).all;
```

Nested preloads from a polymorphic `belongs-to` work even though the parents
returned have different classes. The preloader partitions the cached parents
by class before recursing, and silently skips classes that do not declare the
named child association:

```perl6
Attachment.where({}).preload(attachable => :pictures).all;
```

### has_many / has_one :through

Through-associations are loaded in two batched steps: first the intermediate
collection on the parents, then the source association on the intermediates.
The final cache on each parent is the flattened (`has_many`) or singular
(`has_one`) source value.

```perl6
class User is Model {
  submethod BUILD {
    self.has-many: subscriptions => class => Subscription;
    self.has-many: magazines => through => :subscriptions;
    self.has-one:  profile  => class => Profile;
    self.has-one:  account  => through => :profile;
  }
}

# Two queries: one for subscriptions, one for the magazines they point at.
User.where({}).preload(:magazines).all;

# Same shape for has_one :through.
User.where({}).preload(:account).all;
```

`eager-load(:through-assoc)` joins through the intermediate table to the
source. With `has_many :through`, the JOIN inflates the result set with one
row per join row — pair it with `distinct` (or fall back to `preload`) when
you only need the parents.
