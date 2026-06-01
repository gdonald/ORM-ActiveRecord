# Data Validations

ORM::ActiveRecord supports many forms of data validations, when they occur and if they occur at all.

## Acceptance

The `acceptance` validation requires a field value to be `True` for the `Model` instance to be valid.

```perl6
use ORM::ActiveRecord::Model;

class Contract is Model {
  submethod BUILD {
    self.validate: 'terms', { :acceptance }
  }
}
```

A value of `False` will make the instance invalid and the validated field will contain an error.

```perl6
my $contract = Contract.create({name => 'Offical Document', terms => False});
say $contract.is-valid;
say $contract.errors.terms[0];
```

Output

```shell
False
must be accepted
```

## Confirmation

The `confirmation` validation requires a field to be "confirmed" for the `Model` instance to be valid.  A virtual field with a suffix of "_confirmed" is required.  Combining `confirmation` with `presence` is usually helpful.

```perl6
use ORM::ActiveRecord::Model;

class Client is Model {
  submethod BUILD {
    self.validate: 'email', { :presence, :confirmation }
  }
}

my $client = Client.build({email => 'fred@aol.com'});
say $client.is-invalid;
say $client.errors.email[0];

$client = Client.build({email => 'fred@aol.com', email_confirmation => 'fred@aol.com'});
say $client.is-valid;
```

Output

```shell
False
must be confirmed
True
```

## Exclusion

The `exclusion` validation prevents certain values from being entered.  The excluded values are defined using `in`.

```perl6
use ORM::ActiveRecord::Model;

class Person is Model {
  submethod BUILD {
    self.validate: 'username', { exclusion => { in => <admin superuser> } }
  }
}

my $person = Person.build({username => 'admin'});
say $person.is-valid;
say $person.errors.username[0];
```

Output

```shell
False
is invalid
```

## Format

The `format` validation requires a field value match a specific regular expression.  The format is defined using `with`.

```perl6
use ORM::ActiveRecord::Model;

class Contact is Model {
  submethod BUILD {
    self.validate: 'email', { format => { with => /:i ^<[\w]>+ '@' <[\w]>+ '.' <[\w]>+$/ } }
  }
}

my $contact = Contact.create({email => 'foo'});
say $contact.is-valid;
say $contact.errors.email[0];
```

Output

```shell
False
is invalid
```

## Inclusion

The `inclusion` validation requires a field value exist in a list of pre-defined values.  The allowed values are defined using `in`.

```perl6
use ORM::ActiveRecord::Model;

class Image is Model {
  submethod BUILD {
    self.validate: 'format', { inclusion => { in => <gif jpeg jpg png> } }
  }
}

my $image = Image.build({format => 'foo'});
say $image.is-invalid;
say $image.errors.format[0];
```

Output

```shell
False
is invalid
```

## Length

The `length` validation requires a field value to be a certain length to be valid.

Valid values are defined using `min`, `max`, `is`, or `in`.

### Minimum

A `min` length validation requires the length of the field value be a specified minimum:

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { length => { min => 4 } }
  }
}

my $user = User.build({fname => 'Joe'});
say $user.is-valid;
say $user.errors.fname[0];
```

Output

```shell
False
at least 4 characters required
```

### Maximum

A `max` length validation requires a field value length be less than a specified value.

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { length => { max => 12 } }
  }
}

my $user = User.build({fname => 'Michaelangelo'});
say $user.is-valid;
say $user.errors.fname[0];
```

Output

```shell
False
only 12 characters allowed
```

### In a range

An `in` length validation requires the field value length be within a specified range.

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { length => { in => 4..32 } }
  }
}

my $user = User.build({fname => 'Joe'});
say $user.is-valid;
say $user.errors.fname[0];
```

Output

```shell
False
4 to 32 characters required
```

### Is exactly

An `is` length validation requires a value be an exact size:

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { length => { is => 8 } }
  }
}

my $user = User.build({fname => 'Joe'});
say $user.is-valid;
say $user.errors.fname[0];
```

Output

```shell
False
exactly 8 characters required
```

## Numericality

The `numericality` validation requires a field value to be numerical and of a specific value or in a specific range.  Values can be specified using `gt`, `gte`, `lt`, `lte`, as well as `in` for ranges.

### Less than

```perl6
use ORM::ActiveRecord::Model;

class Book is Model {
  submethod BUILD {
    self.validate: 'pages', { numericality => { lt => 400 } }
  }
}

my $book = Book.create({pages => 400});
say $book.is-valid;
say $book.errors.pages[0];
```

Output

```shell
False
less than 400 required
```

### Less than or equal

```perl6
use ORM::ActiveRecord::Model;

class Book is Model {
  submethod BUILD {
    self.validate: 'pages', { numericality => { lte => 400 } }
  }
}

my $book = Book.create({pages => 401});
say $book.is-valid;
say $book.errors.pages[0];
```

Output

```shell
False
400 or less required
```

### Greater than

```perl6
use ORM::ActiveRecord::Model;

class Book is Model {
  submethod BUILD {
    self.validate: 'pages', { numericality => { gt => 400 } }
  }
}

my $book = Book.create({pages => 400});
say $book.is-valid;
say $book.errors.pages[0];
```

Output

```shell
False
more than 400 required
```

### Greater than or equal

```perl6
use ORM::ActiveRecord::Model;

class Book is Model {
  submethod BUILD {
    self.validate: 'pages', { numericality => { gte => 400 } }
  }
}

my $book = Book.create({pages => 399});
say $book.is-valid;
say $book.errors.pages[0];
```

Output

```shell
False
400 or more required
```

### In a range

```perl6
use ORM::ActiveRecord::Model;

class Book is Model {
  submethod BUILD {
    self.validate: 'pages', { numericality => { in => 400..1000 } }
  }
}

my $book = Book.create({pages => 399});
say $book.is-valid;
say $book.errors.pages[0];
```

Output

```shell
False
400 to 1000 required
```

## Comparison

The `comparison` validation compares a field value against either a literal value or another attribute on the same record. Comparison works for any types Raku can `cmp` — numbers, strings, dates, datetimes.

Options:

- `gt`  — strictly greater than
- `gte` — greater than or equal to
- `lt`  — strictly less than
- `lte` — less than or equal to
- `eq`  — equal to
- `ne`  — other than

If the option value is a `Str` and names an attribute on the record, it resolves to that attribute's current value. Otherwise it is used as a literal.

```perl6
use ORM::ActiveRecord::Model;

class Event is Model {
  submethod BUILD {
    self.validate: 'score',     { comparison => { gt => 0 } }
    self.validate: 'max_score', { comparison => { gte => 'score' } }
    self.validate: 'ends_at',   { comparison => { gt => 'starts_at' } }
  }
}

my $e = Event.build({score => 0, max_score => 10, starts_at => now, ends_at => now});
say $e.is-invalid;
say $e.errors.score[0];
say $e.errors.ends_at[0];
```

Output

```shell
True
must be greater than 0
must be greater than starts_at
```

## Aggregated declaration

The `validates` method accepts one or more field names and a hash of validators to apply to each. It is equivalent to calling `validate` once per field.

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validates: <fname lname>, { :presence, length => { min => 2, max => 32 } }
  }
}

my $u = User.build({fname => '', lname => ''});
say $u.is-invalid;
say $u.errors.fname[0];
say $u.errors.lname[0];
```

Output

```shell
True
must be present
must be present
```

## Custom validator classes

Pass any class (or instance) with a `validate($record)` method to `validates-with`. Named arguments are forwarded to `.new()` when a type object is supplied.

```perl6
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;

class CapValidator {
  has Int $.max = 100;

  method validate($record) {
    if $record.attrs<score> > $!max {
      my $field = Field.new(:name('score'), :type('integer'));
      $record.errors.push(Error.new(:$field, :message("exceeds $!max")));
    }
  }
}

class Game is Model {
  submethod BUILD {
    self.validates-with(CapValidator, :max(50));
  }
}
```

## Block validators

`validates-each` runs the same block once per named field, receiving the record, attribute name, and current value.

```perl6
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;

class User is Model {
  submethod BUILD {
    self.validates-each: <fname lname>, -> $rec, $attr, $value {
      if $value && $value ~~ /^ <:Ll> / {
        my $f = Field.new(:name($attr), :type('string'));
        $rec.errors.push(Error.new(:field($f), :message('must start with capital letter')));
      }
    }
  }
}
```

`validates-each` also accepts the `:if`, `:unless`, `on:`, and `strict`
options (see [Conditionals](conditionals.md)). The guard is evaluated once for
the whole validator — when it skips, the block runs for none of the named
fields. With `strict => True`, a block that records an error instead raises
`X::StrictValidationFailed`.

```perl6
self.validates-each: <fname lname>, &capitalized, { :if => { self.is-active } };
self.validates-each: <fname lname>, &capitalized, { on => { :signup } };
self.validates-each: <fname lname>, &capitalized, { :strict };
```

## Validates associated

When a model owns other records (`has_many`, `has_one`, `has_and_belongs_to_many`, or `belongs_to`), `validates-associated` rolls up each child's `is-valid` into the parent. A failed child contributes a single `is invalid` error on the named association.

```perl6
use ORM::ActiveRecord::Model;

class Book {...}

class Library is Model {
  submethod BUILD {
    self.has-many: books => %(class-name => 'Book');
    self.validates-associated: 'books';
  }
}
```

A custom error message is available through the aggregated `validates` form:

```perl6
self.validates: <books>, { :associated, message => 'has bad children' }
```

`validates-associated` accepts the `:if`, `:unless`, `on:`, and `strict`
options (see [Conditionals](conditionals.md)). With `strict => True`, an
invalid child raises `X::StrictValidationFailed` instead of recording the
`is invalid` error on the association.

```perl6
self.validates-associated: 'books', { :if => { self.name eq 'Audit' } };
self.validates-associated: 'books', { on => { :audit } };
self.validates-associated: 'books', { :strict };
```

## Presence

The `presence` validation requires a field value to exist for the `Model` instance to be valid.

```perl6
use ORM::ActiveRecord::Model;

class User is Model {
  submethod BUILD {
    self.validate: 'fname', { :presence }
  }
}

my $user = User.build;
say $user.is-valid;
say $user.errors.fname[0];
```

Output

```shell
False
must be present
```

## Uniqueness

The `uniqueness` validation requires a field value to be unique with respect to existing field value data in the database.

```perl6
use ORM::ActiveRecord::Model;

class Person is Model {
  submethod BUILD {
    self.validate: 'username', { :uniqueness }
  }
}

my $person = Person.create({username => 'alfred'});
say $person.is-valid;

my $person_2 = Person.build({username => 'alfred'});
say $person_2.is-valid;
say $person_2.errors.username[0];
```

Output

```shell
True
False
must be unique
```

## Unique Scope

The `uniqueness` validation can also contain a scope.  This, for example, can be used for validating uniqueness within a specific foreign key.

```perl6
use ORM::ActiveRecord::Model;

class Subscription {...}

class User is Model {
  submethod BUILD {
    self.has-many: subscriptions => class => Subscription;   
    self.validate: 'fname', { :presence }
  }
}

class Magazine is Model {
  submethod BUILD {
    self.has-many: subscriptions => class => Subscription;
    self.validate: 'title', { :presence }
  }
}

class Subscription is Model {
  submethod BUILD {
    self.belongs-to: user => class => User;
    self.belongs-to: magazine => class => Magazine;
    self.validate: 'user_id', { uniqueness => scope => :magazine_id }
  }
}

my $user = User.create({fname => 'Greg'});
my $magazine = Magazine.create({title => 'Mad'});
my $subscription = Subscription.create({:$user, :$magazine});
say $subscription.is-valid;

my $subscription_2 = Subscription.build({:$user, :$magazine});
say $subscription_2.is-valid;
say $subscription_2.errors.user_id[0];
```

Output

```shell
True
False
must be unique
```
