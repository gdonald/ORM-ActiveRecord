# Validation Conditionals

Validations can be made conditional based on some other method call or criteria.  The available conditionals are `if`, `unless`, and `on`.  With `on` a `create` or `update` life cycle event may be specified.

## If

```perl6
use ORM::ActiveRecord::Model;

class Book is Model {
  submethod BUILD {
    self.validate: 'title', { :presence, :if => { self.returns-true } }
  }

  method returns-true { True }
}

my $book = Book.build;
say $book.is-valid;
say $book.errors.title[0];
```

Output

```shell
False
must be present
```

## Unless

```perl6
use ORM::ActiveRecord::Model;

class Book is Model {
  submethod BUILD {
    self.validate: 'title', { :presence, :unless => { self.returns-false } }
  }

  method returns-false { False }
}

my $book = Book.build;
say $book.is-valid;
say $book.errors.title[0];
```

Output

```shell
False
must be present
```

## On

### Create

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { :presence, on => { :create } }
  }
}

my $user = User.create({});
say $user.is-valid;
say $user.errors.fname[0];
```

Output

```shell
False
must be present
```

### Update

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { :presence, on => { :update } }
  }
}

my $user = User.create({});
say $user.is-valid;

$user.update({fname => ''});
say $user.is-valid;
say $user.errors.fname[0];
```

Output

```shell
True
False
must be present
```
