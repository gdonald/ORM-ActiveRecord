# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Tooling (`ar`)

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

[Unreleased]: https://github.com/gdonald/ORM-ActiveRecord/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/gdonald/ORM-ActiveRecord/compare/v0.1.0...v0.9.0
[0.1.0]: https://github.com/gdonald/ORM-ActiveRecord/releases/tag/v0.1.0
