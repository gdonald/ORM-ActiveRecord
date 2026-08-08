# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.3] - 2026-08-08

### Fixed

- A model over a table with a numeric column (`decimal`, `float`, `money`, and
  the `NUMERIC` / `REAL` types SQLite reports for them) now initializes its
  attributes instead of dying on an unrecognized field type.

## [0.9.2] - 2026-07-21

### Added

- `select(*@cols)` narrows the `SELECT` list to the named columns. A model
  loaded through a narrowed relation carries attrs only for the columns it
  fetched, and saving it writes only those columns. Entries that are not
  columns of the model's table (expressions such as `COUNT(*) OVER ()`) don't
  narrow the load and pair with `pluck` and `distinct`.
- Per-connection cache of column metadata, so repeated introspection of the
  same table reuses the first lookup instead of re-querying the database.

### Changed

- Execution is serialized per connection, so statements and transactions issued
  concurrently against one connection no longer interleave.
- An update writes every attribute it was given, and only those. A blank string
  assigned to a non-text column already became the typed null on create; it now
  clears the column on update as well. Blanking a NOT NULL column raises rather
  than discarding the caller's edit.

### Fixed

- Dropped connections are detected and handled during execution instead of
  surfacing as raw driver errors.
- `save` clears a column whose attribute is set to an undefined value. The
  update builder passed over undefined attributes, so assigning `Nil` left the
  previous value in the row.
- Assigning `Nil` to a `belongs-to` association clears its foreign key (and a
  polymorphic association's type column) instead of writing the association name
  as a column.

## [0.9.1] - 2026-07-11

### Added

- Connection registry that names and stores adapters, with `DB.current` as the
  single resolver used across models, inheritance, and relations.
- Scope traits (`is scope`) for declaring named scopes with cleaner syntax.
- Foreign keys in schema dumps for PostgreSQL and MySQL.

### Changed

- Renamed the `ar` command-line tool to `active-record`.
- Fold wide integer types to a common form during schema introspection.

### Fixed

- Eager loading through `:through` associations.
- Foreign keys in migration dumps.
- Snake-case conversion of table names.
- `build-save` teardown.

## [0.9.0] - 2026-06-24

### Added

#### Async queries

- Run relations and aggregations on worker threads, returning a `Promise`:
  `load-async`, `count-async`, `sum-async`, `average-async`, `minimum-async`,
  `maximum-async`, `calculate-async`, `pluck-async`, `pick-async`, `ids-async`,
  and `find-by-sql-async`.

#### Query predicates

- `LIKE` matching in `where` with automatic wildcard escaping:
  `LikePredicate.contains`, `.starts-with`, and `.ends-with`.
- Database-agnostic JSON / JSONB querying: `JsonPredicate.extract(...).eq` /
  `.ne`, `JsonPredicate.contains`, and `JsonPredicate.has-key`.

#### Bulk writes

- Set-level relation operations: `update-all`, `delete-all`, `destroy-all`,
  `update-counters`, and `touch-all`.
- Class-level shortcuts: `Model.update-all`, `delete-all`, `destroy-all`,
  `destroy-by`, `delete-by`, and `update-counters`.
- Single-statement insert and upsert: `insert` / `insert-bang`,
  `insert-all` / `insert-all-bang`, and `upsert` / `upsert-all` with
  `unique-by` and `update-cols`.

#### Models

- Record copying: `dup` (a new record without an id) and `clone` (preserves id
  and the readonly flag).
- Scoped save and callback suppression: `Model.suppress` and
  `Model.is-suppressed`.
- Per-class strict loading: `Model.strict-loading-by-default` and
  `Model.is-strict-loading-by-default`.

#### Connection and concurrency

- Named advisory locks on PostgreSQL and MySQL (no-op on SQLite):
  `with-advisory-lock`, `get-advisory-lock`, `release-advisory-lock`, and
  `supports-advisory-locks`.
- Request-scoped role and shard switching: `Model.connected-to`,
  `connected-to-many`, `active-role`, `active-shard`, `active-connection`, and
  a `DatabaseSelector` that picks a role based on recent writes.

#### Parallel testing

- Per-worker database support: `worker-index`, `worker-count`,
  `per-worker-dbs-active`, and `apply-worker-suffix`.
- Schema helpers to manage worker databases: `create-test-databases`,
  `migrate-test-databases`, `drop-test-databases`, `reset-test-databases`, and
  `check-test-databases`.

## [0.1.0] - 2026-06-17

Initial release. The feature set below is what ships in 0.1.0.

### Adapters and connection

- PostgreSQL, MySQL, and SQLite adapters behind one interface.
- Connection configuration from `config/application.json` per environment, with
  `DATABASE_URL` override; named connections, pooling, and statement options.

### Models and persistence

- `create` / `save` / `update` / `destroy` and their `-bang` variants.
- Dirty tracking, state predicates (`is-persisted`, `is-new-record`), `reload`,
  `touch`, `increment` / `decrement`, `update-columns`, `update-all`.
- Attribute types, typed virtual attributes, custom types, and serialized
  columns (`serialize` / `store` with JSON and YAML coders).

### Querying

- Lazy relations: `where` / `not`, `order`, `limit`, `offset`, `select`,
  `distinct`, `group` / `having`, `joins`, `or`, CTEs, and raw SQL.
- Finders (`find`, `find-by`, `find-by-bang`, `first`, `last`, `exists`),
  aggregations (`count`, `sum`, `average`, `minimum`, `maximum`, `pluck`,
  `calculate`), and batching.

### Associations

- `belongs-to`, `has-many`, `has-one`, and `has-and-belongs-to-many`.
- `:through` associations, polymorphic associations, composite primary keys,
  counter caches, touch propagation, and dependent strategies.
- Eager loading with `preload`, `includes`, `eager-load`, and `references`,
  including nested loads.

### Validations and errors

- Presence, length, numericality, comparison, format, inclusion / exclusion,
  acceptance, confirmation, uniqueness, and `validates-associated`.
- `validates-with` and `validates-each` for custom rules; conditional and
  context-scoped validation; strict mode.
- An `errors` collection mirroring ActiveModel, with locale-driven messages and
  interpolation tokens.

### Higher-level features

- Single-table inheritance, enums, the Attributes API, normalisation,
  encryption, secure tokens and passwords, nested attributes, soft deletes
  (`discard` / `undiscard`).

### Transactions

- Block-form transactions on `DB.shared` and on models, nested savepoints
  (`:requires-new`), isolation levels, `X::Rollback`, and after-commit /
  after-rollback callbacks.

### Migrations and schema

- A migration DSL (`create-table`, `add-column`, indexes, constraints,
  references, timestamps), reversible migrations, and schema introspection.

### Tooling (`active-record`)

- Migrations: `migrate`, `rollback`, `up` / `down`, and `db:*` tasks
  (`db:create`, `db:drop`, `db:reset`, `db:setup`, `db:seed`, `db:prepare`,
  `db:version`, `db:migrate:status`, `db:migrate:redo`,
  `db:abort_if_pending_migrations`, `db:test:prepare`).
- Schema dump / load: `db:schema:dump`, `db:schema:load`,
  `db:structure:dump`, `db:schema:cache:dump`.
- Generators: `generate model` / `migration` / `scope` / `validator`, and
  `destroy`.
- Runtime: `console`, `runner`, `dbconsole`, `notes`, `stats`.

### Logging and instrumentation

- Structured SQL logging (level, formatter, sink), timing and bound values,
  colourised output, and query-log tags.
- A pub/sub instrumentation layer for SQL, instantiation, and transaction
  events.

### Test helpers

- A transactional test wrapper, a YAML fixture loader (with interpolation and
  label-based deterministic ids and cross-file references), and a database
  cleaner with deletion / truncation / transaction strategies.

[Unreleased]: https://github.com/gdonald/ORM-ActiveRecord/compare/v0.9.1...HEAD
[0.9.1]: https://github.com/gdonald/ORM-ActiveRecord/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/gdonald/ORM-ActiveRecord/compare/v0.1.0...v0.9.0
[0.1.0]: https://github.com/gdonald/ORM-ActiveRecord/releases/tag/v0.1.0
