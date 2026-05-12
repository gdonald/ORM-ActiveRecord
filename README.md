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

### License

Copyright (c) 2019-2026 Greg Donald

This software is licensed under the Artistic License 2.0.

[![GitHub](https://img.shields.io/github/license/gdonald/ORM-ActiveRecord?color=aa0000)](https://github.com/gdonald/ORM-ActiveRecord/blob/master/LICENSE)
