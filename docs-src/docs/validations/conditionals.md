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

### Custom contexts

`on:` accepts any context name, not just `:create` or `:update`. A validator
tagged with a custom context only runs when the caller asks for it.

```perl6
use ORM::ActiveRecord::Model;

class Signup is Model {
  submethod BUILD {
    self.validate: 'email',    { :presence }
    self.validate: 'password', { :presence, on => { :step_two } }
  }
}

my $s = Signup.build({email => 'a@b.com'});
say $s.is-valid;                            # True — step_two skipped by default
say $s.is-invalid(:context<step_two>);     # True — step_two now fires
say $s.errors.password[0];                  # must be present
```

A validator tagged with `on:` that does not match the active context is silently
skipped; validators with no `on:` always run.

### Sticky context

Set `validation-context=` on the record to make subsequent `is-valid`/`is-invalid`
calls (and `save`) use a particular context. Explicit `:context` arguments still
win over the sticky setter.

```perl6
my $s = Signup.build({email => 'a@b.com'});
$s.validation-context = 'step_two';
say $s.is-invalid;          # True — uses sticky context
$s.validation-context = Str; # clear
say $s.is-valid;            # True — back to default
```

### Re-running validations

Every call to `is-valid` / `is-invalid` clears `errors` and re-runs every
applicable validator. There is no result cache — repeated calls reflect the
current attribute state, not a stale snapshot:

```perl6
my $s = Signup.build({email => ''});
$s.is-invalid;            # error pushed onto $s.errors
$s.email = 'a@b.com';
$s.is-valid;              # errors cleared, no new errors pushed
```
