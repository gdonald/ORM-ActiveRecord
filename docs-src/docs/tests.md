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

## Running with prove6

You can run the entire test suite with `prove6` from [TAP::Harness](https://github.com/perl6/tap-harness6).

```shell
$ prove6
```

You should get output similar to this:

```shell
t/000-meta.t6 ........................... ok
t/001-basic.t6 .......................... ok
t/002-validate-acceptance.t6 ............ ok
t/002-validate-build-save.t6 ............ ok
t/002-validate-build.t6 ................. ok
t/002-validate-confirmation.t6 .......... ok
t/002-validate-create.t6 ................ ok
t/002-validate-exclusion.t6 ............. ok
t/002-validate-format.t6 ................ ok
t/002-validate-inclusion.t6 ............. ok
t/002-validate-integer-numericality.t6 .. ok
t/002-validate-length.t6 ................ ok
t/002-validate-presence-if-unless.t6 .... ok
t/002-validate-presence-on-create.t6 .... ok
t/002-validate-presence-on-update.t6 .... ok
t/002-validate-unique-scope.t6 .......... ok
t/002-validate-uniqueness.t6 ............ ok
t/002-validate-update.t6 ................ ok
t/003-update-save.t6 .................... ok
t/004-model-custom-errors.t6 ............ ok
t/004-model-dynamic-errors.t6 ........... ok
t/004-model-foreign-key.t6 .............. ok
t/004-model-is-dirty.t6 ................. ok
t/004-model-where.t6 .................... ok
t/005-callback-after-create.t6 .......... ok
t/005-callback-after-save.t6 ............ ok
t/005-callback-after-update.t6 .......... ok
t/005-callback-before-create.t6 ......... ok
t/005-callback-before-save.t6 ........... ok
t/005-callback-before-update.t6 ......... ok
All tests successful.
Files=30, Tests=220,  15 wallclock secs
Result: PASS
```

## Running a single test file

You can run a single test file using Rakudo Perl 6:

```shell
perl6 -Ilib t/001-basic.t6
```

You should get output similar to this:

```shell
1..5
ok 1 -
ok 2 -
ok 3 -
ok 4 -
ok 5 -
```
