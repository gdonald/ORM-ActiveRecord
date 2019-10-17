
# ORM::ActiveRecord

ORM::ActiveRecord is an [object-relational mapping](https://en.wikipedia.org/wiki/Object-relational_mapping) module for Raku that mostly follows the [Active Record Pattern](https://en.wikipedia.org/wiki/Active_record_pattern).

## Documentation

[http://docs.rakuist.io/orm-activerecord](http://docs.rakuist.io/orm-activerecord)

## Install using zef

```
zef install --/test ORM::ActiveRecord
```

`--/test` is suggested because you probably don't have a test database setup.

## Example Usage

```perl6
use User;
use Page;

my User $user = User.create({fname => 'Greg', lname => 'Donald'});

Page.create({:$user, name => 'Raku'});

say $user.pages.first.name;
Perl 6

say $page.user.fullname;
Greg Donald

my User $alfred = User.create({fname => 'Alfred E.', lname => 'Neuman'});

$page.update({user => $alfred});

say $page.user.fullname
Alfred E. Neuman
```

## Build Status

[![Build Status](https://travis-ci.org/rakuist/ORM-ActiveRecord.svg?branch=master)](https://travis-ci.org/rakuist/ORM-ActiveRecord)

## License

ORM::ActiveRecord is released under the [Artistic License 2.0](https://opensource.org/licenses/Artistic-2.0)

## TODO

- [ ] Model: scopes
- [ ] Model: has-many => through
- [ ] Migration generator
- [ ] Model generator
