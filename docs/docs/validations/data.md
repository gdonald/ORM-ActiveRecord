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

## Presence

The `presence` validation requires a field value to simply exist for the `Model` instance to be valid.

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
