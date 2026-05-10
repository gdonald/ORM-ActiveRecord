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
$ raku -Ilib t/0020-basic.rakutest
```

Test files live under `t/` and use the `.rakutest` extension. They follow the
naming pattern `NNNN-name.rakutest` where `NNNN` is a sort key, not a stable
identifier — feel free to renumber when reorganising.
