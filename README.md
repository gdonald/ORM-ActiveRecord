
## ORM::ActiveRecord

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
User $user = User.find(1);
Page $page = $user.pages.first;

say $user.fullname;
Greg Donald

say $page.name;
Perl 6

say $page.user.fname;
Greg
```
