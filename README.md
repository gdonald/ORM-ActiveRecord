# ORM::ActiveRecord

ORM::ActiveRecord is an [object-relational mapping](https://en.wikipedia.org/wiki/Object-relational_mapping) module for Raku that *mostly* follows the [Active Record Pattern](https://en.wikipedia.org/wiki/Active_record_pattern).

## Documentation

[http://docs.rakuist.io/orm-activerecord](http://docs.rakuist.io/orm-activerecord)

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

Please see the [documentation](http://docs.rakuist.io/orm-activerecord) for more examples.

## Build Status

[![Build Status](https://travis-ci.org/rakuist/ORM-ActiveRecord.svg?branch=master)](https://travis-ci.org/rakuist/ORM-ActiveRecord)

## License

ORM::ActiveRecord is released under the [Artistic License 2.0](https://opensource.org/licenses/Artistic-2.0)

## Features

- [x] Migrations
- [x] Validations
- [x] Callbacks
- [x] Scopes
- [x] Dirty
- [x] Custom Errors
- [x] PostgreSQL support

## TODO

- [ ] Model: has-many => through
- [ ] Migration generator
- [ ] Model generator
- [ ] Support for MySQL, SQLite, and Oracle.
