# Model Callbacks

ORM::ActiveRecord supports callbacks that can be performed during various life cycle events.

The available events are:

- Save: `before-save` / `around-save` / `after-save`
- Create: `before-create` / `around-create` / `after-create`
- Update: `before-update` / `around-update` / `after-update`
- Destroy: `before-destroy` / `around-destroy` / `after-destroy`
- Validation: `before-validation` / `after-validation`
- Initialize: `after-initialize`
- Find: `after-find` (fires only when a record is loaded from the database)
- Touch: `after-touch`

For callbacks that wait until the surrounding transaction's outcome is
decided — `after-commit`, `after-rollback`, and the per-action variants
(`after-create-commit`, `after-update-commit`, `after-destroy-commit`,
`after-save-commit`) — see [Transactional Callbacks](transactions.md#transactional-callbacks).

## After Create

```perl6
use ORM::ActiveRecord::Model;

class Log is Model {};

class Client is Model {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-create: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was created';
    Log.create({:$log});
  }
}

# No logs to start with
say Log.count == 0;

# Creating a record creates a log
my $client = Client.create({ email => 'fred@aol.com' });
say Log.count == 1;

# Updating a record does not create a log
$client.email = 'barney@compuserve.net';
$client.save;
say Log.count == 1;
```

Output

```shell
True
True
True
```

## After Save

```perl6
use ORM::ActiveRecord::Model;

class Log is Model {};

class Client is Model {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-save: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was saved';
    Log.create({:$log});
  }
}

# No logs to start with
say Log.count == 0;

# Creating a record creates a log
my $client = Client.create({ email => 'fred@aol.com' });
say Log.count == 1;

# Updating a record also creates a log
$client.email = 'barney@compuserve.net';
$client.save;
say Log.count == 2;
```

Output

```shell
True
True
True
```

## After Update

```perl6
use ORM::ActiveRecord::Model;

class Log is Model {};

class Client is Model {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-update: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was updated';
    Log.create({:$log});
  }
}

# No logs to start with
say Log.count == 0;

# Creating a record does not create a log
my $client = Client.create({ email => 'fred@aol.com' });
say Log.count == 0;

# Updating a record creates a log
$client.email = 'barney@compuserve.net';
$client.save;
say Log.count == 1;
```

Output

```shell
True
True
True
```

## Before Create

```perl6
use ORM::ActiveRecord::Model;

class Client is Model {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-create: -> { self.lowercase-email };
  }

  method lowercase-email {
    self.email .= lc;
  }
}

# Email is lower-cased before the record is created
my $client = Client.create({ email => 'Fred@AOL.com' });
say $client.email eq 'fred@aol.com';

# Email is not lower-cased before the record is updated
$client.email = 'BARNEY@compuserve.NET';
$client.save;
say $client.email eq 'BARNEY@compuserve.NET';
```

Output

```shell
True
True
```

## Before Save

```perl6
use ORM::ActiveRecord::Model;

class Client is Model {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-save: -> { self.lowercase-email };
  }

  method lowercase-email {
    self.email .= lc;
  }
}

# Email is lower-cased before the record is created
my $client = Client.create({ email => 'Fred@AOL.com' });
say $client.email eq 'fred@aol.com';

# Email is also lower-cased before the record is updated
$client.email = 'BARNEY@compuserve.NET';
$client.save;
say $client.email eq 'barney@compuserve.net';
```

Output

```shell
True
True
```

## After Destroy

```perl6
use ORM::ActiveRecord::Model;

class Log is Model {};

class Client is Model {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-destroy: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was destroyed';
    Log.create({:$log});
  }
}

my $client = Client.create({ email => 'fred@aol.com' });
say Log.count == 0;

$client.destroy;
say Log.count == 1;
```

Output

```shell
True
True
```

## Before Destroy

```perl6
use ORM::ActiveRecord::Model;

class Client is Model {
  submethod BUILD {
    self.before-destroy: -> { say 'about to destroy ' ~ self.email };
  }
}

my $client = Client.create({ email => 'fred@aol.com' });
$client.destroy;
```

Output

```shell
about to destroy fred@aol.com
```

If you want to remove a record without firing destroy callbacks (or any other
side effects), use `delete` instead. `delete` issues the `DELETE` directly and
skips the `before-destroy` and `after-destroy` callbacks.

## Before Update

```perl6
use ORM::ActiveRecord::Model;

class Client is Model {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-update: -> { self.lowercase-email };
  }

  method lowercase-email {
    self.email .= lc;
  }
}

# Email is not lower-cased before the record is created
my $client = Client.create({ email => 'Fred@AOL.com' });
say $client.email eq 'Fred@AOL.com';

# Email is lower-cased before the record is saved
$client.save;
say $client.email eq 'fred@aol.com';
```

Output

```shell
True
True
```

## Around Callbacks

`around-save`, `around-create`, `around-update`, and `around-destroy` wrap
the corresponding write operation. The block receives a `&yield` argument;
calling it runs the wrapped operation (along with its `before-*`/`after-*`
callbacks), so code before and after the call to `&yield` becomes the
"before" and "after" halves of the wrapper. Forgetting to call `&yield`
halts the operation (`save` / `destroy` returns `False`).

```perl6
class Client is Model {
  submethod BUILD {
    self.around-save: -> &yield {
      my $started = now;
      &yield();
      my $elapsed = now - $started;
      say "save took {$elapsed.fmt('%.4f')}s";
    };
  }
}
```

## Validation, Initialize, Find, Touch

```perl6
class Client is Model {
  submethod BUILD {
    self.before-validation: -> { self.email .= trim };
    self.after-validation:  -> { say 'errors so far: ' ~ self.errors.count };
    self.after-initialize:  -> { self.role //= 'guest' };
    self.after-find:        -> { say 'loaded ' ~ self.id };
    self.after-touch:       -> { self.bump-cache };
  }
}
```

- `after-initialize` fires for every freshly constructed instance (both
  records loaded from the database and ones built in memory).
- `after-find` fires only when the instance was hydrated from the database.
- `after-touch` fires after a successful call to `.touch(...)`.

## Method-name Handlers

Any callback registration accepts a method name (`Str`) instead of a block.
The method is dispatched on `self`.

```perl6
class Client is Model {
  submethod BUILD {
    self.before-save: 'lowercase-email';
    self.after-create: 'send-welcome-email';
  }

  method lowercase-email { self.email .= lc }
  method send-welcome-email { ... }
}
```

## Multiple Callbacks per Event

Multiple callbacks registered for the same event fire in declaration order.

```perl6
class Client is Model {
  submethod BUILD {
    self.after-save: -> { say 'first'  };
    self.after-save: -> { say 'second' };
    self.after-save: -> { say 'third'  };
  }
}
```

## `:prepend`

Use `:prepend` to put a callback at the front of its chain instead of
appending it.

```perl6
self.after-save: -> { say 'runs before the rest' }, :prepend;
```

## Conditional Callbacks (`:if` / `:unless`)

Both `:if` and `:unless` accept a `Block`, a `Str` method name, or an
`Array` of either. With an `Array`, every entry must be satisfied for the
callback to run.

```perl6
class Client is Model {
  submethod BUILD {
    self.after-save: -> { self.send-welcome },
      :if(-> { self.is-new-record });
    self.after-save: -> { self.send-billing },
      :if('is-paid'),
      :unless('is-archived');
    self.after-save: -> { self.audit },
      :if(['is-paid', -> { self.email.chars > 0 }]);
  }

  method is-paid     { ... }
  method is-archived { ... }
}
```

## Halting the Chain

A callback can stop the rest of its chain (and abort the surrounding
`save` / `destroy`) by returning `False` or by throwing
`X::Callback::Abort`.

```perl6
use ORM::ActiveRecord::Errors::X;

class Client is Model {
  submethod BUILD {
    self.before-save: -> {
      return False unless self.email.chars;
      True;
    };
    self.before-destroy: -> {
      die X::Callback::Abort.new if self.is-protected;
    };
  }
}
```

## Introspection: `set-callback` / `skip-callback`

Callbacks can be added or removed by tag at runtime. Pass a `:tag` when
registering so they can later be looked up or removed.

```perl6
class Client is Model {
  submethod BUILD {
    self.before-save: -> { self.normalize }, :tag<normalize>;
  }
}

my $c = Client.build({ email => 'fred@aol.com' });

$c.has-callback(:event<save>, :timing<before>, :tag<normalize>);  # True
$c.callback-tags(:event<save>, :timing<before>);                  # ('normalize',)

# Disable just this one callback for this instance
$c.skip-callback(:event<save>, :timing<before>, :tag<normalize>);

# Or add a new one
$c.set-callback(
  :event<save>, :timing<before>,
  :handler(-> { ... }),
  :tag<custom>,
);
```

## Custom Chain Terminator

By default, a callback halts the chain when it returns the value `False`
(or when `X::Callback::Abort` is thrown). The terminator can be customised
per event/timing by passing a `Block` that decides whether a result aborts.

```perl6
$c.set-callback-terminator(
  :event<save>, :timing<before>,
  :block(-> $result { $result === 0 || $result === False }),
);
```
