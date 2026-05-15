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

## Has One

A model can declare a one-to-one association with `has-one`. The associated table holds the foreign key pointing back at the owner, mirroring the `belongs-to` side.

```perl6
class Profile {...} # forward declaration

class User is Model {
  submethod BUILD {
    self.has-one: profile => class => Profile;
  }
}

class Profile is Model {
  submethod BUILD {
    self.belongs-to: user => class => User;
  }
}

my $user = User.create({fname => 'Greg'});
Profile.create({:$user, bio => 'Raku enthusiast'});

say $user.profile.bio;
```

Output

```shell
Raku enthusiast
```

When no associated record exists, `has-one` returns `Nil`.

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

## Has One Through

A `has-one` association can use `through` to reach a single related record via a join model.

In this example a `user` has access to an `account` through the `profile` model:

```perl6
class Profile {...} # stub
class Account {...} # stub

class User is Model {
  submethod BUILD {
    self.has-one: profile => class => Profile;
    self.has-one: account => through => :profile;
  }
}

class Profile is Model {
  submethod BUILD {
    self.belongs-to: user => class => User;
    self.belongs-to: account => class => Account;
  }
}

class Account is Model {}

my $user = User.create({fname => 'Greg'});
my $account = Account.create({name => 'gdonald'});
Profile.create({:$user, :$account, bio => 'Raku enthusiast'});

say $user.account.name;
```

Output

```shell
gdonald
```

When no join record exists, `has-one` `through` returns `Nil`.

## Has And Belongs To Many

A many-to-many relationship without an intermediate model is declared with `has-and-belongs-to-many` on both sides. The link rows live in a dedicated join table whose name is the two pluralized table names joined alphabetically with an underscore (e.g. `posts` + `tags` → `posts_tags`). The join table only needs the two foreign-key columns.

```perl6
class Tag {...} # forward declaration

class Post is Model {
  submethod BUILD {
    self.has-and-belongs-to-many: tags => class => Tag;
  }
}

class Tag is Model {
  submethod BUILD {
    self.has-and-belongs-to-many: posts => class => Post;
  }
}

my $post = Post.create({title => 'First'});
my $raku = Tag.create({name => 'raku'});
my $orm  = Tag.create({name => 'orm'});

$post.add-tag($raku);
$post.add-tag($orm);

say $post.tags.map(*.name).sort.join(', ');
say $raku.posts.first.title;
```

Output

```shell
orm, raku
First
```

Each association adds three write helpers, named after the association:

- `add-<singular>($record)` — insert a single link row
- `remove-<singular>($record)` — delete one link row
- `clear-<plural>` — delete every link row for this owner

```perl6
$post.remove-tag($orm);
say $post.tags.map(*.name).join(', ');

$post.clear-tags;
say $post.tags.elems;
```

Output

```shell
raku
0
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
