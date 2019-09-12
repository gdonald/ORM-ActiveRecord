
### ORM::ActiveRecord

Object-relational mapping module for Perl 6.

#### Install from CPAN

```
zef install --/test ORM::ActiveRecord
```

#### Example Migrations

Migrations contain an `up` and a `down`.

**db/migrate/001-create-users.pm6**

```perl6
use ORM::ActiveRecord::Migration;

class CreateUsers is Migration {
  method up {
    self.create-table: 'users', [
      fname => { :string, limit => 32 },
      lname => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'users';
  }
}
```

**db/migrate/002-create-pages.pm6**

```perl6
use ORM::ActiveRecord::Migration;

class CreatePages is Migration {
  method up {
    self.create-table: 'pages', [
      user => { :reference },
      name => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'pages';
  }
}
```

#### Run Migrations

```shell
> ar
```

Migration options:

```shell
> ar up      # runs all pending migrations
> ar down    # resets all migrations, be careful!
> ar up:1    # runs 1 pending migrations
> ar down:1  # resets 1 previously completed migration
```

#### Add Models and their Relationships and Validations

```perl6
use ORM::ActiveRecord;

class Page {...} # forward declaration

class User is ActiveRecord is export {
  submethod BUILD {
    self.has-many: pages => class => Page;

    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
    self.validate: 'lname', { :presence, length => { min => 4, max => 32 } }
  }

  method fullname {
    self.fname ~ ' ' ~ self.lname;
  }
}

class Page is ActiveRecord is export {
  submethod BUILD {
    self.belongs-to: user => class => User;

    self.validate: 'name', { :presence, length => { min => 4, max => 32 } }
  }
}
```

#### Usage

```perl6
use User;
use Page;

my User $user = User.create({fname => 'Greg', lname => 'Donald'});

Page.create({:$user, name => 'Perl 6'});

say $user.pages.first.name;
Perl 6

say $page.user.fullname;
Greg Donald

my User $alfred = User.create({fname => 'Alfred E.', lname => 'Neuman'});

$page.update({user => $alfred});

say $page.user.fullname
Alfred E. Neuman
```

#### Run Tests

```
$ prove -v --exec=perl6 --ext=t6
```

#### Status

[![Build Status](https://travis-ci.org/gdonald/ORM-ActiveRecord.svg?branch=master)](https://travis-ci.org/gdonald/ORM-ActiveRecord)

#### License

ORM::ActiveRecord is released under the [Artistic License 2.0](https://opensource.org/licenses/Artistic-2.0)
