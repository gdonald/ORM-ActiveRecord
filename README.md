
### ORM::ActiveRecord

Object-relational mapping module for Perl 6.

```perl6
use ORM::ActiveRecord;

class User is ActiveRecord {
  submethod BUILD {
    self.has-many: pages => class => Page;
  }

  method fullname {
    self.fname ~ ' ' ~ self.lname;
  }
}

class Page is ActiveRecord {
  submethod BUILD {
    self.belongs-to: user => class => User;
  }
}
```

```perl6
my User $user = User.find(1);
my Page $page = $user.pages.first;

say $user.fullname;
Greg Donald

say $page.name;
Perl 6

say $page.user.fname;
Greg
```

#### Run Tests:

```
$ prove -v --exec=perl6 --ext=t6
```

## Status

[![Build Status](https://travis-ci.org/gdonald/ORM-ActiveRecord.svg?branch=master)](https://travis-ci.org/gdonald/ORM-ActiveRecord)

#### License

ORM::ActiveRecord is released under the [Artistic License 2.0](https://opensource.org/licenses/Artistic-2.0)
