# Tests

ORM::ActiveRecord includes a full test suite. It runs against PostgreSQL, MySQL,
and SQLite. `./test.raku` cycles through all three; any adapter that isn't
reachable is skipped with a message describing how to enable it.

## Database configuration

There are two ways to point the suite at a database:

**1. `DATABASE_URL` env var** (preferred — what `./test.raku` and CI use):

```
DATABASE_URL=postgres://user:pass@localhost:5432/ar_test?schema=public
DATABASE_URL=mysql://root:root@127.0.0.1:3306/ar_test
DATABASE_URL=sqlite:db/test.sqlite3
```

For local multi-adapter runs, `./test.raku` reads per-adapter overrides from
`AR_PG_URL`, `AR_MYSQL_URL`, and `AR_SQLITE_URL`. The PostgreSQL default is
built from `config/application.json` if present.

**2. `config/application.json`** (single-adapter; what `bin/ar` reads when
`DATABASE_URL` is unset). Pick the example matching your adapter:

```
cp config/application.json-pg-example     config/application.json
cp config/application.json-mysql-example  config/application.json
cp config/application.json-sqlite-example config/application.json
```

Then edit credentials as needed.

## Running the suite

`./test.raku` is the canonical entry point. With no `DATABASE_URL` set, it
cycles through PostgreSQL, MySQL, and SQLite — probing each first and skipping
unreachable adapters with a message describing how to enable them. With
`DATABASE_URL` set, it runs once against that adapter (this is what CI does
per matrix entry).

```shell
$ ./test.raku
```

When all three adapters are reachable you get a runtimes summary at the end:

```shell
==> Runtimes
  postgres    26.60s
  mysql       26.37s
  sqlite      22.59s
  total       75.65s
```

## Running with prove6

To run the suite once against your default adapter — what `config/application.json`
or `DATABASE_URL` points at — invoke `prove6` directly:

```shell
$ prove6 -Ilib t
```

## Running a single test file

```shell
$ raku -Ilib t/0040-basic.rakutest
```

Test files live under `t/` and use the `.rakutest` extension. They follow the
naming pattern `NNNN-name.rakutest` where `NNNN` is a sort key, not a stable
identifier — feel free to renumber when reorganising.

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
