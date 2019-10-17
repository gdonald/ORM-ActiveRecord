# ORM::ActiveRecord

The latest version of this documentation lives at [http://docs.rakuist.io/orm-activerecord/](http://docs.rakuist.io/orm-activerecord/).

## Synopsis

ORM::ActiveRecord is an [object-relational mapping](https://en.wikipedia.org/wiki/Object-relational_mapping) module for Rakudo Perl 6 that *mostly* follows the [Active Record Pattern](https://en.wikipedia.org/wiki/Active_record_pattern).

## Example Usage

```perl6
use User;
use Page;

my User $user = User.create({fname => 'Greg'});
my Page $page = Page.create({:$user, name => 'Raku'});

say $user.pages.first.name;
say $page.user.fname;

my User $alfred = User.create({fname => 'Alfred'});
$page.update({user => $alfred});

say $page.user.fname
```

Output:

```shell
Raku
Greg
Alfred
```

## Install

ORM::ActiveRecord can be installed using the zef module installation tool:

```
zef install --/test ORM::ActiveRecord
```

`--/test` is suggested because you probably don't have a test database setup.
You can of course [setup a test database](/tests/#database-configuration).
