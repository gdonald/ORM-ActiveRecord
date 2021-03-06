# Models

ORM::ActiveRecord supports model relationships, the layer of your app that is responsible for managing data and business logic.

## Basic Example

In this example the `user` has many `pages` and the reverse is also true, a `page` belongs to a `user.

```perl6
use ORM::ActiveRecord::Model;

class Page {...} # forward declaration

class User is Model is export {
  submethod BUILD {
    self.has-many: pages => class => Page;
  }
}

class Page is Model is export {
  submethod BUILD {
    self.belongs-to: user => class => User;
  }
}
```

Perl 6 does single-pass compilation.  You must provide forward declarations `{...}` for any models that have not been defined yet but need to be used in has-many or belongs-to relationships.

This allows chaining method calls together like this:

```perl6
my $user = User.create({fname => 'Greg'});
my $page = Page.create({:$user, name => 'Rakuist'});

say $user.pages.first.name;
say $page.user.fname;
```

Output

```shell
Rakuist
Greg
```

Access to lower level foreign key relationships is supported.

```perl6
say $page.user_id == $user.id;
```

Output

```shell
True
```

## Where Query

To search for a particular record you can issue a `where` query with a hash for parameters.

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { :presence }
  }
}

my $fred = User.create({fname => 'Fred'});
my $barney = User.create({fname => 'Barney'});

my $result = User.where({fname => 'Fred'}).first;
say $result == $fred;
```

Output

```shell
True
```

## Scope

Frequently used queries can be made into a `scope` for easier access.  Scopes live on the model type, not on an instance of the type, so we use `$?CLASS` to point to the existing class.  The contents of the scope is a lazy block that is only evaluated when required.

```perl6
use ORM::ActiveRecord::Model;

class Image is Model {
  $?CLASS.scope: 'jpgs', -> { $?CLASS.where({ext => 'jpg'}) }

  submethod BUILD {
    self.validate: 'name', { :presence }
    self.validate: 'ext', { :presence, inclusion => { in => <jpg png> } }
  }
}

my $foo = Image.create({name => 'foo', ext => 'jpg'});
my $bar = Image.create({name => 'bar', ext => 'jpg'});
my $baz = Image.create({name => 'baz', ext => 'png'});
say Image.count;

my @images = Image.jpgs.all;
say any(@images) == $foo;
say any(@images) == $bar;
say none(@images) == $baz;
```

Output

```shell
3
True
True
True
```

## Has Many Through

You can access related models using `has-many` with `through`.

In this example a `user` has access to `magazines` through the `subscriptions` model:

```perl6
class Subscription {...} # stub

class User is Model {
  submethod BUILD {
    self.has-many: subscriptions => class => Subscription;
    self.has-many: magazines => through => :subscriptions;
  }
}

class Magazine is Model {}

class Subscription is Model {
  submethod BUILD {
    self.belongs-to: user => class => User;
    self.belongs-to: magazine => class => Magazine;
  }
}

my $user = User.create({fname => 'Greg'});
my $magazine = Magazine.create({title => 'Mad'});
Subscription.create({:$user, :$magazine});

say $user.magazines.first == $magazine;
```

Output

```shell
True
```

## Is Dirty

If you modify a record it will need to be persisted back to the database or the changes will eventually be lost.  To know if you actually have pending changes that need to be saved you can call `is-dirty` on the model instance.

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { :presence }
  }
}

my $user = User.create({fname => 'Fred'});
say $user.is-dirty;

$user.fname = 'John';
say $user.is-dirty;

$user.save;
say $user.is-dirty;
```

Output

```shell
False
True
False
```
