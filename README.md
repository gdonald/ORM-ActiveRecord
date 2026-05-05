# ORM::ActiveRecord

ORM::ActiveRecord is an [object-relational mapping](https://en.wikipedia.org/wiki/Object-relational_mapping) module for Raku that *mostly* follows the [Active Record Pattern](https://en.wikipedia.org/wiki/Active_record_pattern).

## Documentation

[https://gdonald.github.io/ORM-ActiveRecord/](https://gdonald.github.io/ORM-ActiveRecord/)

## Install using zef

```
zef install --/test ORM::ActiveRecord
```

`--/test` is suggested because you probably don't have a test database setup.

## Simple Example

```perl6
my $user = User.create({fname => 'Greg'});
my $page = Page.create({:$user, name => 'Rakuist'});

say $user.pages.first.name;
Rakuist

say $page.user.fname;
Greg

my $alfred = User.create({fname => 'Fred'});
$page.update({user => $fred});

say $page.user.fname;
Fred
```

Please see the [documentation](https://gdonald.github.io/ORM-ActiveRecord/) for more examples.

## Build Status

[![.github/workflows/raku.yml](https://github.com/gdonald/ORM-ActiveRecord/workflows/.github/workflows/raku.yml/badge.svg)](https://github.com/gdonald/ORM-ActiveRecord/actions)

## License

ORM::ActiveRecord is released under the [Artistic License 2.0](https://opensource.org/licenses/Artistic-2.0)

## Features

- [x] Model:
    - [x] Associations
        - [x] belongs-to
        - [x] has-many
        - [x] has-many -> through
    - [x] Querying
        - [x] where, all, first, last, count
        - [x] find (raises `X::RecordNotFound` on miss)
        - [x] find-by, find-by-or-die
        - [x] take
        - [x] exists
        - [x] order, limit, offset, select
        - [x] pluck, ids
        - [x] Chainable relations (`User.where(...).order(...).limit(...).all`)
    - [x] Persistence
        - [x] create, save, update, build
        - [x] save-or-die, update-or-die, create-or-die (raise `X::RecordInvalid`)
        - [x] destroy (with callbacks), delete (skip callbacks), destroy-all
        - [x] Automatic created_at / updated_at management
    - [x] Validations
        - [x] Conditionals: if, unless, on, create, update
        - [x] Acceptance
        - [x] Confirmation
        - [x] Exclusion
        - [x] Format
        - [x] Inclusion
        - [x] Length
        - [x] Minimum
        - [x] Maximum
        - [x] In a range
        - [x] Is exactly
        - [x] Numericality
        - [x] Less than
        - [x] Less than or equal
        - [x] Greater than
        - [x] Greater than or equal
        - [x] In a range
        - [x] Presence
        - [x] Uniqueness
        - [x] Unique Scope
    - [x] Callbacks
        - [x] after: create, save, update, destroy
        - [x] before: create, save, update, destroy
    - [x] Scopes
    - [x] Dirty
    - [x] Custom Errors
- [x] Migrations
    - [x] Tables, columns, indexes, foreign-key references
    - [x] add-timestamps / remove-timestamps
    - [x] Datetime / timestamp column type
- [x] PostgreSQL support
- [x] Bound parameters everywhere (SQL injection safe)

## Roadmap

A detailed list of remaining work — including more associations, eager loading,
locking, additional adapters, generators, and other features — lives in
[ROADMAP.md](ROADMAP.md).

