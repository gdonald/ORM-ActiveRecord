# Tests

The suite has two halves: the `prove6` tests under `t/` and the `behave` specs
under `specs/`. Both run against PostgreSQL, MySQL, and SQLite.

## Pointing the tests at a database

The tests connect the same way the rest of the ORM does — `DATABASE_URL`, or
`config/application.json` when it is unset (see [Adapters](adapters.md) for the
full configuration reference). The adapter you point at is the adapter the
tests exercise:

```
DATABASE_URL=postgres://user:pass@localhost:5432/ar_test?schema=public
DATABASE_URL=mysql://root:root@127.0.0.1:3306/ar_test
DATABASE_URL=sqlite:db/test.sqlite3
```

To exercise all three, run the suite once per `DATABASE_URL`.

## Running the prove6 tests

The `t/` tests use the standard Raku test harness. Run them all with `prove6`:

```shell
$ prove6 -Ilib t
```

Test files use the `.rakutest` extension, grouped into feature-area subfolders:
`meta/`, `migration/`, `validation/`, `callbacks/`, `associations/`, `query/`,
`model/`, `adapter/`, `transactions/`, `infra/`. `prove6` recurses into
subdirectories automatically.

Run a single file directly:

```shell
$ raku -Ilib t/model/basic.rakutest
```

## Running the behave specs

The `specs/` specs use [BDD::Behave](https://github.com/gdonald/BDD-Behave).
Run them all, or a single spec file:

```shell
$ behave specs                              # the whole specs/ tree
$ behave specs/model/basic-spec.raku        # one spec file
```

## Running the specs in parallel

`behave` can run spec files concurrently, each against its own database copy so
they never trample each other's schema and data. First provision the per-worker
databases — set the test environment's `parallel` key to the worker count and
use `active-record … --parallel` (see [Migrations » Parallel test databases](migrations.md#parallel-test-databases)):

```json
{ "test": { "parallel": 4, "primary": { "adapter": "pg", "name": "ar_test" } } }
```

```shell
$ active-record createdb --parallel    # create the N per-worker copies
$ active-record migrate  --parallel    # migrate them
$ active-record check    --parallel    # verify all N exist and are migrated
```

Then run behave with a matching worker count:

```shell
$ behave --parallel=4 specs
```

Each worker connects to its own copy, named by suffixing the configured
database with `_<worker-index>`:

| Configured                | Worker 0            | Worker 1            |
| ------------------------- | ------------------- | ------------------- |
| pg/mysql `ar_test`        | `ar_test_0`         | `ar_test_1`         |
| sqlite `db/test.sqlite3`  | `db/test_0.sqlite3` | `db/test_1.sqlite3` |
| sqlite `:memory:`         | per-process (unchanged) | … |

behave runs in its default isolated mode — one subprocess per spec file —
recycling a fixed set of N worker slots; each slot reuses its own database
across every spec file dispatched to it. The ORM derives the suffix from
behave's own `BEHAVE_WORKER_INDEX` / `BEHAVE_WORKER_COUNT`, so there is nothing
else to keep in sync. Creating and migrating N copies costs N × a full
`db/migrate/` pass up front.

> Run `active-record check --parallel` first. Launching specs against missing or
> un-migrated worker databases otherwise produces confusing "no such table"
> errors deep in the run; `active-record check` reports them up front and changes nothing
> (`behave` itself is database-agnostic and cannot verify your schema).

## Adapter-aware test skipping

Some tests only make sense against one adapter — a test that exercises a
PostgreSQL `RETURNING` quirk has nothing to assert against MySQL, and a test
for a MySQL `TINYINT(1)` round-trip has nothing to assert against PostgreSQL.
`ORM::ActiveRecord::Support::TestSkip` provides four subs to express that
without re-implementing the same `parse-database-url + plan + skip + exit`
boilerplate in every file.

```raku
use Test;
use ORM::ActiveRecord::Support::TestSkip;

# 1. "skip the rest of this file when the active adapter is sqlite"
skip-on(:adapter<sqlite>);

# 2. "only run if the active adapter is mysql"
only-on(:adapter<mysql>);

# 3. multi-adapter form — accepts a list
skip-on(:adapter<<sqlite mysql>>);
only-on(:adapter<<pg mysql>>);

# 4. predicates if you want to branch instead of bail
if adapter-matches(:adapter<pg>) {
  # PG-only setup
}

my $name = configured-adapter-name();   # 'pg' | 'mysql' | 'sqlite' | Str
```

**Active adapter resolution** — `configured-adapter-name` reads
`DATABASE_URL` and normalises the scheme alias (`postgres`, `postgresql`,
`mysql2`, `mariadb`, `sqlite3`, …) to one of `pg` / `mysql` / `sqlite`. It
returns `Str` (undefined) when no `DATABASE_URL` is set.

The project's own `config/application.json` is **not** consulted by default,
because that would silently route every test through one adapter even when
the developer wanted to exercise another. To opt in (e.g. for a CLI tool or
runtime-style test that does follow the project config), pass
`:config-path('config/application.json')` or `:check-config`.

**Skip semantics** — both `skip-on` and `only-on`:

- emit a single `plan 1; skip "…"; exit 0` when they decide to skip
- return `False` (and do nothing else) when they decide to continue, so they
  can be called unconditionally at the top of a file
- treat "no `DATABASE_URL` set" as "let the test decide" — neither will skip
  in that case, so adapter-specific tests can still try a localhost default
  and fall back to a connect-probe skip of their own

**Recognised aliases** — both the user-supplied `:adapter` argument and the
configured-adapter value are normalised through the same map, so any of these
work and mean the same thing:

| Canonical | Aliases accepted                |
| --------- | ------------------------------- |
| `pg`      | `postgres`, `postgresql`        |
| `mysql`   | `mysql2`, `mariadb`             |
| `sqlite`  | `sqlite3`                       |
