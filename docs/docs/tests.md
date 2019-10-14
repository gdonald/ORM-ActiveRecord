# Tests

ORM::ActiveRecord includes a full test suite.  To run it you need to first configure a local test database.

## Database configuration

A database configuration file is expected to be at `config/application.json`.  The format looks like this:

```json
{
    "db": {
        "schema": "public",
        "name": "ar",
        "user": "postgres",
        "password": ""
    }
}
```

You can copy the `config/application.json-example` file to `config/application.json` and then change the parameters as required for your particular setup.

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
