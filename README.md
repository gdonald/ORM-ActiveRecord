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
    - [x] belongs-to
    - [x] has-many
    - [x] has-many -> through
    - [x] where: all, first, count
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
        - [x] after: create, save, update
        - [x] before: create, save, update
    - [x] Scopes
    - [x] Dirty
    - [x] Custom Errors
- [x] Migrations
- [x] PostgreSQL support

## TODO

- [ ] Includes: for has-many records
- [ ] Migration generator
- [ ] Model generator
- [ ] Support for MySQL, SQLite, and Oracle.

