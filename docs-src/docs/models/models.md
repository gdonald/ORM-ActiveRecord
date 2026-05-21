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

### Singular proxy methods

For each `has-one` declaration, the owner gets `build-<assoc>`, `create-<assoc>`, and `create-<assoc>-or-die` methods. They construct the associated record with the foreign key already set to the owner's primary key. `build-` returns an unsaved record; `create-` saves and returns the record (with errors if invalid); `create-...-or-die` saves and raises `X::RecordInvalid` when the target fails validation.

```perl6
my $user = User.create({fname => 'Greg'});

my $draft = $user.build-profile({bio => 'unsaved'});
my $saved = $user.create-profile({bio => 'persisted'});
my $forced = $user.create-profile-or-die({bio => 'forced'});
```

These methods are not available on `has-one :through` declarations.

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

## Collection Proxy Methods

A `has-many` accessor returns a *collection proxy* — an Array of records with extra methods that act on the association as a whole. Iteration, indexing, and `.elems` still behave like a plain Array, so existing code that assigns the result to `@arr` keeps working.

```perl6
class Post {...}

class Author is Model {
  submethod BUILD {
    self.has-many: posts => class => Post;
  }
}

class Post is Model {
  submethod BUILD {
    self.belongs-to: author => class => Author;
  }
}

my $alice = Author.create({name => 'alice'});
```

**Building and creating through the association** sets the foreign key automatically:

```perl6
my $draft   = $alice.posts.build({title => 'wip'});       # unsaved, fkey set
my $live    = $alice.posts.create({title => 'live'});     # saved
my $forced  = $alice.posts.create-or-die({title => 'pinned'});
```

**Push** moves an existing record into the collection (sets its fkey and saves). Raku reserves `<<` for hyperops, so the proxy uses `.push` and `.append`:

```perl6
my $orphan = Post.create({title => 'orphan'});
$alice.posts.push($orphan);   # also: $alice.posts.append($orphan)
```

**Membership queries** without re-running SQL:

```perl6
$alice.posts.is-empty;        # Bool
$alice.posts.size;            # same as .elems
$alice.posts.length;          # same as .elems
$alice.posts.count;           # same as .elems
$alice.posts.exists;          # Bool — non-empty?
$alice.posts.exists($id);     # Bool — id in collection?
$alice.posts.exists({title => 'live'});
$alice.posts.find($id);       # raises X::RecordNotFound if missing
```

**Mutators** — `delete`, `destroy`, `clear`, and `replace`:

```perl6
$alice.posts.delete($live);   # nullifies fkey (or follows dependent: strategy)
$alice.posts.destroy($draft); # destroys the row outright
$alice.posts.clear;           # unlinks every member
$alice.posts.replace([$keep, $newone]);
```

`delete` and `clear` use the association's `dependent:` strategy when one is set (`:destroy`, `:delete-all`, `:nullify`); otherwise they default to nullifying the foreign key.

**Association extensions** mix a role of extra methods into the collection. The methods see `self` as the collection (so `self.records`, `self.elems`, `self.first` all work):

```perl6
role PostsExtension {
  method recent-titles {
    self.records.sort({ .attrs<created_at> }).reverse.map({ .attrs<title> });
  }
}

class Author is Model {
  submethod BUILD {
    self.has-many: posts => %(
      class     => Post,
      extension => PostsExtension,
    );
  }
}

say $alice.posts.recent-titles.join(', ');
```

## Polymorphic Belongs To

A `belongs-to` association can target rows from more than one table by declaring it polymorphic. The owning table stores two columns: `<name>_id` for the foreign key and `<name>_type` for the class name of the related row.

The migration sets up both columns at once via `:reference, :polymorphic`:

```perl6
class CreateAttachments is Migration {
  method up {
    self.create-table: 'attachments', [
      name => { :string, limit => 80 },
      attachable => { :reference, :polymorphic },
    ]
  }

  method down {
    self.drop-table: 'attachments';
  }
}
```

That creates `attachments.attachable_id` (integer) and `attachments.attachable_type` (string). No foreign-key constraint is emitted because the referenced table varies per row.

Declare the polymorphic side on the model with `:polymorphic` instead of `class => SomeClass`. The other models do not need any extra declaration to be linkable:

```perl6
class User is Model { }
class Post is Model { }

class Attachment is Model {
  submethod BUILD {
    self.belongs-to: attachable => :polymorphic;
  }
}

my $user = User.create({fname => 'Greg', lname => 'Donald'});
my $post = Post.create({title => 'Hello'});

my $avatar = Attachment.create({name => 'avatar.png', attachable => $user});
my $banner = Attachment.create({name => 'banner.jpg', attachable => $post});

say $avatar.attachable.WHAT.^name;   # User
say $banner.attachable.WHAT.^name;   # Post
```

Output

```shell
User
Post
```

Assigning a record fills in both `<name>_id` and `<name>_type` automatically; reading `$record.<name>` looks the type column up at runtime and returns an instance of the appropriate class. Reading an unset polymorphic association returns `Nil`.

The class name is resolved at runtime via the global symbol table, so any class accessible by short name works. If a model is loaded into a deeper package, list the candidates explicitly:

```perl6
self.belongs-to: attachable => { :polymorphic, classes => (User, Post) };
```

## Polymorphic Has Many

A model on the inverse side of a polymorphic `belongs-to` declares the collection with `has-many` and `as => '<name>'`. The `<name>` is the same polymorphic name used on the `belongs-to` side. Several owner classes can each declare `has-many :pictures, as => 'imageable'` against the same `pictures` table; each owner's collection is scoped to rows whose `imageable_type` matches that owner's class.

The migration is unchanged from a regular polymorphic reference:

```perl6
class CreatePictures is Migration {
  method up {
    self.create-table: 'pictures', [
      name => { :string, limit => 80 },
      imageable => { :reference, :polymorphic },
    ]
  }

  method down {
    self.drop-table: 'pictures';
  }
}
```

Each owner declares `has-many ... as => '<name>'`. The target model declares the polymorphic `belongs-to` exactly once:

```perl6
class Picture {...}

class User is Model {
  submethod BUILD {
    self.has-many: pictures => %(class => Picture, as => 'imageable');
  }
}

class Post is Model {
  submethod BUILD {
    self.has-many: pictures => %(class => Picture, as => 'imageable');
  }
}

class Picture is Model {
  submethod BUILD {
    self.belongs-to: imageable => :polymorphic;
  }
}

my $user = User.create({fname => 'Greg', lname => 'Donald'});
my $post = Post.create({title => 'Hello'});

Picture.create({name => 'avatar.png', imageable => $user});
Picture.create({name => 'banner.jpg', imageable => $user});
Picture.create({name => 'hero.png',   imageable => $post});

say $user.pictures.elems;
say $post.pictures.elems;
```

Output

```shell
2
1
```

Reading `$owner.pictures` filters on both `imageable_id = $owner.id` and `imageable_type = '<OwnerClass>'`, so collections never leak across owner types. Reassigning a picture (`$pic.update({imageable => $post})`) moves it from one owner's collection to the other on the next read.

## Polymorphic Resolution

Two methods control how polymorphic associations move between Raku classes and the strings stored in `<name>_type`. Both have sensible defaults; override them when the stored string needs to differ from the short class name or when the owner needs custom dispatch.

### Target-side: `polymorphic-name`

`polymorphic-name` is called on the **target** model whenever its identity needs to be written into a `<name>_type` column. The default returns the short class name (the part after the last `::`).

Override it to write a different string. Useful when:

- the class lives inside a module and you want the bare name in the database (or vice-versa),
- you renamed a class but do not want to migrate the existing `_type` values,
- two model classes need to share a stored type string.

```perl6
class User is Model {
  method polymorphic-name { 'Person' }
}

my $u = User.create({fname => 'Greg', lname => 'Donald'});
my $a = Attachment.create({name => 'avatar.png', attachable => $u});
say $a.attrs<attachable_type>;
```

Output

```shell
Person
```

The same method is consulted when scoping a `has-many :as` collection, when nullifying / deleting children, and when collection-proxy methods (`push`, `replace`, etc.) write through to a polymorphic child.

### Owner-side: `polymorphic-class-for`

When reading a polymorphic association, the owner asks `polymorphic-class-for($assoc-name, $type-name)` for the class that matches the stored string. Override it on the owner to customize how stored strings map back to classes.

The default implementation:

- if the association was declared with `classes => (...)`, return the candidate whose `polymorphic-name` matches the stored string (or `Nil` if none match),
- otherwise resolve `$type-name` as a fully-qualified package via `GLOBAL`, supporting nested names like `App::Post`.

```perl6
class Attachment is Model {
  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
  }

  method polymorphic-class-for(Str:D $assoc, Str:D $type) {
    given $type {
      when 'Person'    { return User }
      when 'App::Post' { return App::Post }
      default          { return Nil }
    }
  }
}
```

If the hook returns `Nil`, reading the association returns `Nil` instead of raising. That is the right behavior when stored type strings can drift (e.g., rows imported from another system).

### Module-qualified storage

`polymorphic-name` may return a fully-qualified name. The default resolver walks the package separators, so the round-trip works without any further configuration:

```perl6
module App {
  our class Post is Model {
    method polymorphic-name { 'App::Post' }
  }
}

my $post = App::Post.create({title => 'Hello'});
my $a    = Attachment.create({name => 'banner.jpg', attachable => $post});

say $a.attrs<attachable_type>;
say Attachment.find($a.id).attachable.WHAT.^name;
```

Output

```shell
App::Post
App::Post
```

This is the most common reason to override `polymorphic-name`: keep the database value stable when classes are reorganized into deeper namespaces.

## Self-Referential Associations

A model can declare associations that point at its own class. The classic shape is an employee who reports to another employee, and who in turn has zero or more direct reports.

The migration only needs a nullable foreign-key column. There is no `:reference` shorthand because that always builds a FK constraint against `<name>s`, which would aim at the wrong table for a self-join; declare the column as an integer instead.

```perl6
class CreateEmployees is Migration {
  method up {
    self.create-table: 'employees', [
      name => { :string, limit => 64 },
      manager_id => { :integer },
    ]
  }

  method down {
    self.drop-table: 'employees';
  }
}
```

Both sides live on the same model. The `belongs-to` resolves the parent row; the `has-many` needs `foreign-key:` because the column does not follow the owner-class naming convention (`employee_id`). Mark the parent side `optional => True` so the root of the tree can save without a manager — `belongs-to` is required by default.

```perl6
class Employee is Model {
  submethod BUILD {
    self.belongs-to: manager => %(class => Employee, optional => True);
    self.has-many: subordinates => %(class => Employee, foreign-key => 'manager_id');
  }
}

my $ceo  = Employee.create({name => 'Alice'});
my $vp1  = Employee.create({name => 'Bob',   manager => $ceo});
my $vp2  = Employee.create({name => 'Carol', manager => $ceo});

say $vp1.manager.attrs<name>;
say $ceo.subordinates.map(*.attrs<name>).sort.join(', ');
```

Output

```shell
Alice
Bob, Carol
```

The top-level row has no manager: `$ceo.manager` returns `Nil`, and `$ceo.attrs<manager_id>` is `0`. Reassigning a subordinate is the usual `update`:

```perl6
$vp1.update({manager => $vp2});
say $ceo.subordinates.elems;
say $vp2.subordinates.elems;
```

Output

```shell
1
1
```

## Class Name Override

Every association kind accepts a `class-name:` option in addition to `class:`. Pass the class name as a string and the lookup is deferred until access time, when the name is resolved through the `GLOBAL::` package stash. This is useful when the association name does not match the target class, when the target class is defined later in load order, or when the class identifier is only available as a string.

Both the single-pair form and the hash form work the same way:

```perl6
class User is Model {
  submethod BUILD {
    self.has-many:   pages   => class-name => 'Page';        # Pair form
    self.has-one:    profile => %(class-name => 'Profile');  # Hash form
  }
}

class Page is Model {
  submethod BUILD {
    self.belongs-to: user => class-name => 'User';
  }
}
```

`class-name:` works on every association kind: `belongs-to`, `has-many` (including `:through`), `has-one` (including `:through`), and `has-and-belongs-to-many`. It can be mixed with other options in the hash form:

```perl6
self.has-many: magazines => %(through => :subscriptions, class-name => 'Magazine');
```

Nested module names are supported by separating with `::`:

```perl6
self.belongs-to: owner => class-name => 'App::Models::User';
```

If the name cannot be resolved at access time, `class-name:` raises an error naming the offending string.

## Foreign Key and Primary Key Overrides

By default an association uses the conventional column names:

- `belongs-to :user` reads `user_id` on this table and matches it against `id` on the `users` table.
- `has-many :pages` matches this row's `id` against `user_id` on the `pages` table.
- `has-one :profile` matches this row's `id` against `user_id` on the `profiles` table.

Two options override that convention:

- `foreign-key:` renames the column that holds the foreign key. It always names the column on the side of the relationship that physically stores the link.
- `primary-key:` renames the column whose value is matched. It defaults to `id` — change it when the related row is identified by something other than the surrogate primary key (e.g. a country code, a slug).

### Renaming the foreign-key column

When the same table joins to another table more than once, the second column cannot follow the default naming. Use `foreign-key:` on both sides:

```perl6
class User {...}

class Article is Model {
  submethod BUILD {
    self.belongs-to: author => %(class => User, foreign-key => 'author_id');
  }
}

class User is Model {
  submethod BUILD {
    self.has-many: articles => %(class => Article, foreign-key => 'author_id');
  }
}

my $user    = User.create({fname => 'Greg', lname => 'Donald'});
my $article = Article.create({:title<Hello>, :body<Body>, author => $user});

say $article.attrs<author_id>;           # Greg's id
say $user.articles.first.attrs<title>;   # Hello
```

`has-one` accepts `foreign-key:` the same way:

```perl6
class Passport {...}

class User is Model {
  submethod BUILD {
    self.has-one: passport => %(class => Passport, foreign-key => 'owner_id');
  }
}

class Passport is Model {
  submethod BUILD {
    self.belongs-to: owner => %(class => User, foreign-key => 'owner_id');
  }
}
```

### Joining on a non-id primary key

`primary-key:` is the right option when the value you join on is not the surrogate `id`. A canonical example is a region keyed by a stable code:

```perl6
class Town {...}

class Region is Model {
  submethod BUILD {
    self.has-many: towns => %(
      class       => Town,
      primary-key => 'code',
      foreign-key => 'region_code',
    );
  }
}

class Town is Model {
  submethod BUILD {
    self.belongs-to: region => %(
      class       => Region,
      primary-key => 'code',
      foreign-key => 'region_code',
    );
  }
}

my $usa    = Region.create({code => 'US', name => 'United States'});
my $austin = Town.create({region => $usa, name => 'Austin'});

say $austin.attrs<region_code>;        # US
say $usa.towns.map(*.attrs<name>);     # (Austin)
```

On the `belongs-to` side, `primary-key:` names the column on the target table; on the `has-many` / `has-one` side, it names the column on the owning model whose value is matched against the foreign key.

## Inverse Of

When a `has-many` or `has-one` knows the name of the matching `belongs-to` on the other side, each child returned by the collection gets a back-pointer to the same in-memory parent. Iterating `parent.children` then `child.parent` returns the same object instance — no second query, no second copy.

```perl6
class Page {...}

class User is Model {
  submethod BUILD {
    self.has-many: pages => class => Page;
  }
}

class Page is Model {
  submethod BUILD {
    self.belongs-to: user => class => User;
  }
}

my $u = User.find($id);
my @pages = $u.pages;

@pages.first.user.WHERE == $u.WHERE;     # True — same instance
```

### Automatic inverse detection

Auto-detection runs when the association is declared with only `class:` and/or `class-name:`. It searches the target model's `belongs-to` declarations and uses one whose class matches the owning model — if and only if exactly one match exists.

Auto-detection is **skipped** when any of these options appear on the owning side: `foreign-key`, `primary-key`, `through`, `as`, `polymorphic`. In those cases the heuristic isn't reliable, and an explicit `inverse-of:` is required to wire the back-pointer.

### Explicit `inverse-of:`

Pass `inverse-of:` in the hash form to name the inverse association by hand. This is required whenever overrides disable auto-detection, and useful when the back-pointer name does not match Rails-like convention.

```perl6
class Article {...}

class User is Model {
  submethod BUILD {
    self.has-many: articles => %(
      class       => Article,
      foreign-key => 'author_id',
      inverse-of  => :scribe,
    );
  }
}

class Article is Model {
  submethod BUILD {
    self.belongs-to: scribe => %(
      class       => User,
      foreign-key => 'author_id',
    );
  }
}

my $u = User.find($id);
$u.articles.first.scribe.WHERE == $u.WHERE;   # True
```

`inverse-of:` accepts either a `:pair` form (`inverse-of => :scribe`) or a string (`inverse-of => 'scribe'`). It applies to `has-many` and `has-one`; the back-pointer is populated on every record returned from the collection or singular accessor. If no inverse is declared and auto-detection cannot run, the back-pointer is not wired and each `child.parent` access reloads from the database.

## Optional and Required Belongs-To

By default every `belongs-to` is **required**: validation fails unless the record has either an in-memory parent instance or a non-zero foreign-key value. This matches the Rails 5+ default and turns a missing parent into a clear validation error rather than a `NOT NULL` constraint violation at insert time.

```perl6
class Page is Model {
  submethod BUILD {
    self.belongs-to: user => class => User;
  }
}

my $orphan = Page.new(:id(0), :record({attrs => {name => 'Home'}}));
say $orphan.is-valid;                    # False
say $orphan.errors.errors.first.message; # must exist
$orphan.save;                            # returns False, no row inserted
```

Pass `optional => True` (or the alias `required => False`) to allow the record to save without a parent. Use this for self-referential trees (the root has no parent), polymorphic targets that are sometimes detached, or any foreign-key column that is genuinely nullable.

```perl6
class Employee is Model {
  submethod BUILD {
    self.belongs-to: manager => %(class => Employee, optional => True);
  }
}

my $ceo = Employee.create({name => 'Alice'});   # saves, manager_id stays 0
```

`optional` and `required` work the same way on a polymorphic `belongs-to`:

```perl6
self.belongs-to: attachable => %(:polymorphic, :optional);
```

The check runs before the row is written. It accepts the parent in either form:

- `attrs<user>` set to a `Model` instance, or
- `attrs<user_id>` (or the `foreign-key:` override column) set to a non-zero integer.

For a polymorphic `belongs-to`, both `<name>_id` and `<name>_type` must be set.

`is-belongs-to-optional($name)` reports whether the named association is optional, useful when introspecting a model's relations.

## Dependent

The `dependent:` option on an association decides what happens to the related rows when the owner is destroyed. The five strategies match Rails:

- `:destroy` — call `destroy` on each related record. `before-destroy` / `after-destroy` callbacks run on every child.
- `:delete-all` — bulk-delete related rows in one SQL statement. No child callbacks fire.
- `:nullify` — keep related rows in place and set their foreign-key column(s) to `NULL`.
- `:restrict-with-error` — refuse to destroy the owner if any related rows exist. `destroy` returns `False` and an error is recorded in `owner.errors`.
- `:restrict-with-exception` — refuse to destroy the owner if any related rows exist. `destroy` raises `X::DeleteRestrictionError`.

Strategy names accept either underscores (`'restrict_with_error'`) or hyphens (`'restrict-with-error'`); both forms resolve to the same dispatch.

```perl6
class Comment {...}

class Post is Model {
  submethod BUILD {
    self.has-many: comments => %(class => Comment, dependent => 'destroy');
  }
}
```

`dependent:` works on `has-many` and `has-one`. The strategy is applied before the owner's row is deleted, so child-side `before-destroy` callbacks always see the owner still present in the database.

For polymorphic `has-many :as`, `:nullify` sets both the `<as>_id` and `<as>_type` columns to `NULL`.

The two restrict strategies are pre-flight checks. They run before `before-destroy` and never partially apply: if children exist, no other side effect occurs.

```perl6
class Library is Model {
  submethod BUILD {
    self.has-many: books => %(class => Book, dependent => 'restrict-with-error');
  }
}

my $lib = Library.create({name => 'Main'});
Book.create({library => $lib, title => 'AR'});

$lib.destroy;                          # returns False
$lib.errors.errors[0].message;         # Cannot delete record because dependent books exist
```

`belongs-to` accepts `dependent: 'destroy'` (or `'delete'`) to cascade upward — destroying the child first destroys (or deletes) its parent. Polymorphic `belongs-to` is skipped because the target class is not known until access time.

`has-many :through` does not currently honor `dependent:` on the through-association — declare it on the underlying join model's association instead.

## Counter Cache

The `counter-cache:` option on a `belongs-to` keeps a running count of children on the parent table. Each `create` increments the counter; each `destroy` decrements it; reassigning the foreign key to a different parent moves the count from the old parent to the new one.

`counter-cache => True` uses the default column name `<child-table>_count` on the parent. Pass a string for a custom column name.

```perl6
class Shop is Model {
  submethod BUILD {
    self.has-many: books => %(class => Book);
  }
}

class Book is Model {
  submethod BUILD {
    self.belongs-to: shop => %(
      class         => Shop,
      counter-cache => True,
    );
  }
}
```

The parent table needs a non-null integer column for the counter, defaulting to zero:

```perl6
self.create-table: 'shops', [
  name        => { :string, limit => 64 },
  books_count => { :integer, null => False, default => 0 },
];
```

For a custom column name, pass the column name as a string:

```perl6
self.belongs-to: librarian => %(
  class         => Librarian,
  counter-cache => 'managed_books_ct',
);
```

A child can declare counter caches on more than one `belongs-to` — both counters are kept in sync independently.

Counter caches are wired into `save` and `destroy`. Methods that intentionally bypass the persistence layer — `delete` (no callbacks), `update-column`, `update-columns`, `update-all`, `delete-all`, `insert-all`, and `upsert` — do not adjust the counter, matching Rails. Polymorphic `belongs-to` is skipped because the target class is not known until access time.

## Touch

The `touch:` option on a `belongs-to` bumps timestamps on the parent whenever the child is saved or destroyed. `touch => True` updates `updated_at`. Pass a column name (string) to update that column **and** `updated_at`:

```perl6
class Item is Model {
  submethod BUILD {
    self.belongs-to: shop => %(
      class => Shop,
      touch => 'reviewed_at',  # or `touch => True` for updated_at only
    );
  }
}
```

The same persistence-bypassing methods listed under [Counter Cache](#counter-cache) also bypass `touch:`. Polymorphic `belongs-to` is skipped.

## Autosave

The `autosave:` option on a `belongs-to` controls whether the parent is saved when the child is saved. The default is "save new parents only" — i.e. an unsaved parent instance gets saved first so the foreign-key column can carry its id. `autosave => True` also re-saves existing parents on every child save; `autosave => False` disables autosaving entirely.

```perl6
class Book is Model {
  submethod BUILD {
    self.belongs-to: author => %(
      class    => Author,
      autosave => True,
    );
  }
}

my $author = Author.new(:id(0), :record({attrs => {name => 'X'}}));
my $book   = Book.create({title => 'Y', author => $author});
# $author now has an id, $book.attrs<author_id> points to it
```

`autosave:` on `has-many` / `has-one` is recognised but inert until the in-memory collection proxy (phase 6.4 of the roadmap) lands — there is no place yet to attach unsaved children to a parent.

## Validate (Cascade)

The `validate:` option on a `belongs-to` cascades validation. With `validate => True`, validating the child also validates the parent; if the parent is invalid, the child accumulates a single `<assoc> is invalid` error.

```perl6
class Article is Model {
  submethod BUILD {
    self.belongs-to: author => %(
      class    => Author,
      validate => True,
    );
  }
}
```

Per-field parent errors are not merged — Rails' `validates_associated` rolls up to one summary message, and that is what `validate => True` does here.

## Strict Loading

`strict-loading => True` on any association causes lazy access to raise `X::StrictLoadingViolationError`. Use it to surface N+1 patterns; once eager loading lands (phase 7), the exception will be suppressed when the association was pre-loaded.

```perl6
class Order is Model {
  submethod BUILD {
    self.has-many: line-items => %(
      class           => LineItem,
      strict-loading  => True,
    );
  }
}

$order.line-items;   # → dies with X::StrictLoadingViolationError
```

The exception's `model` and `association` accessors expose the model class name and the association name for diagnostics.

## Through Source and Source Type

`has-many :through` and `has-one :through` resolve the target class by looking up a `belongs-to` on the join model whose name matches the singular of the through-association. When the through-association name doesn't follow that convention, name the underlying `belongs-to` with `source:`.

```perl6
class User is Model {
  submethod BUILD {
    self.has-many: subscriptions => %(class => Subscription);
    # The has-many name 'readers' doesn't match the join model's belongs-to ':user',
    # so name it explicitly via source:
    self.has-many: readers => %(
      class   => User,
      through => :subscriptions,
      source  => :user,
    );
  }
}
```

When the source `belongs-to` is polymorphic, `source-type:` filters to a single target type and resolves the class:

```perl6
self.has-many: messages => %(
  through     => :subscriptions,
  source      => :receivable,
  source-type => 'Message',
);
```

## Disable Joins (Through)

`disable-joins => True` on a `has-many :through` or `has-one :through` issues two separate queries — first against the join table, then against the target — instead of one `LEFT JOIN`. This is the right choice when the target lives on a different shard or schema than the join table.

```perl6
self.has-many: magazines => %(
  through       => :subscriptions,
  disable-joins => True,
);
```

The result set is identical to the `LEFT JOIN` form.

## Query Constraints

`query-constraints:` on a `has-many` declares a composite foreign-key match against multiple columns. Pass an array of column names on the child; the owner's natural foreign-key column (`<owner-singular>_id`) is filled from `id`, and every other column is filled from `%!attrs` of the same name on the owner.

```perl6
class Org is Model {
  submethod BUILD {
    self.has-many: docs => %(
      class             => Doc,
      query-constraints => ['org_id', 'user_id'],
    );
  }
}
```

With this declaration, `org.docs` fetches `WHERE org_id = ? AND user_id = ?`, with both values pulled from the owner. Full composite-primary-key support — including the inverse `belongs-to` direction — lands in phase 12.9.

## Association Scope

`scope:` accepts a block that narrows the association's relation just before it runs. The block receives the partial `Query` (already keyed to the owner's foreign key) and returns a query with any additional `where` / `order` / `limit` applied. Works on `has-many`, `has-one`, `belongs-to`, and `has-and-belongs-to-many`.

```perl6
class Author is Model {
  submethod BUILD {
    self.has-many: articles => %(
      class => Article,
      scope => -> $q { $q.where({ :published }) },
    );

    self.has-many: top-articles => %(
      class       => Article,
      foreign-key => 'author_id',
      scope       => -> $q { $q.where({ :published }).order('rank').limit(5) },
    );

    self.has-one: profile => %(
      class => Profile,
      scope => -> $q { $q.where({ :visible }) },
    );
  }
}

class Article is Model {
  submethod BUILD {
    self.belongs-to: author => %(
      class => Author,
      scope => -> $q { $q.where({ is_active => True }) },
    );
  }
}
```

`author.articles` returns published articles only. `author.top-articles` chains `where`, `order`, and `limit` together. `author.profile` returns the visible profile (or `Nil` if none match). `article.author` returns `Nil` when the parent row exists but fails the `is_active` filter — the scope is applied after the foreign-key lookup.

### Argument-Taking Scopes

If the block takes additional positional parameters, pass them when invoking the association:

```perl6
class Author is Model {
  submethod BUILD {
    self.has-many: ranked-articles => %(
      class       => Article,
      foreign-key => 'author_id',
      scope       => -> $q, $min { $q.where({ rank => $min..* }) },
    );
  }
}

$author.ranked-articles(5);   # only rank >= 5
$author.ranked-articles(9);   # only rank >= 9
```

The first block parameter is always the partial `Query`. Anything after that is filled from positional arguments at the call site.

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
