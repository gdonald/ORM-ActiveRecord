# Model Callbacks

ORM::ActiveRecord supports callbacks that can be performed during various life cycle events.

These callbacks currently include `after-create`, `after-save`, `after-update`, `before-create`, `before-save`, and `before-update`.

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
