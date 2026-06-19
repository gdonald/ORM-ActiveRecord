# Contributing

Thanks for your interest in ORM::ActiveRecord. This guide covers how to get set
up, run the tests, and match the conventions the codebase already follows.

## Getting set up

Install the dependencies:

```
zef install --deps-only .
```

The tests run against PostgreSQL, MySQL, and SQLite. SQLite needs no setup. For
PostgreSQL and MySQL, create the databases and point the test environment at
them in `config/application.json` (see [Adapters](docs-src/docs/adapters.md) for
the config shape). You can also override the primary connection with
`DATABASE_URL`.

Create and migrate the configured databases:

```
raku -Ilib bin/ar createdb
raku -Ilib bin/ar migrate
```

## Running the tests

`test.raku` is the entry point. It runs the `t/` suite (via `prove6`) and the
`specs/` suite (via `behave`) against each configured adapter:

```
./test.raku                      # all adapters
./test.raku --adapter=sqlite     # one adapter
./test.raku --prove6             # only the t/ suite
./test.raku --behave             # only the specs/ suite
```

Run a single file while iterating:

```
prove6 -Ilib t/validation/length.rakutest
behave specs/validation/length-spec.raku
```

After editing a library module, clear stale precompilation if behave's bulk
discovery starts failing:

```
rm -rf lib/.precomp
```

## Conventions

### `t/` and `specs/` mirror each other

Every test in `t/` (Test / `prove6`) has a counterpart in `specs/`
(BDD::Behave), and vice versa. Shared setup code lives under `specs/lib/`. When
you change behaviour, update both sides in the same commit.

### Register new modules in `META6.json`

When you add a `lib/**/*.rakumod`, add it to the `provides` section in the same
step. `prove6 -Ilib` resolves by path and won't catch a missing entry, but zef
and the metadata test will.

### Migrations

Migration files are `db/migrate/NNN-kebab-name.raku` with a zero-padded numeric
prefix. Generated migrations use a timestamp prefix instead. Avoid MySQL
reserved words in table and column names — the DDL emitter does not quote
identifiers.

### Documentation

User-facing docs live under `docs-src/docs/` and are wired into
`docs-src/mkdocs.yml`. When a change adds a feature or changes behaviour, update
the matching page in the same commit; the docs should track the `specs/`.

### Code style

- Separate logical chunks with blank lines.
- Use descriptive names, even in small scopes.
- Keep comments short and factual; prefer a test over a comment.
- Method names cannot end in `!` or `?`: port `save!` to `save-bang` and
  `valid?` to `is-valid`. Underscores become hyphens.

## Submitting changes

1. Branch from `main`.
2. Make your change with tests on both the `t/` and `specs/` sides.
3. Run `./test.raku` and make sure it passes.
4. Update the docs and `CHANGELOG.md` under `[Unreleased]`.
5. Open a pull request describing the change and why.

## Reporting issues

Open an issue with the adapter and version, a minimal model and migration that
reproduces the problem, and the SQL or error you see (set `DISABLE-SQL-LOG`
unset to view the SQL).
