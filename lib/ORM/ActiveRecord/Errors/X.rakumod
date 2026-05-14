
class X::IrreversibleMigration is Exception is export {}

class X::RecordInvalid is Exception is export {
  has $.record;
  has @.messages;
  method message {
    'Validation failed: ' ~ @!messages.join(', ');
  }
}

class X::RecordNotFound is Exception is export {
  has Str $.model;
  has $.id;
  method message {
    "Couldn't find {$!model}" ~ ($!id.defined ?? " with id={$!id}" !! '');
  }
}

class X::ReadOnlyRecord is Exception is export {
  has Str $.model;
  method message {
    $!model.defined ?? "$!model is marked as readonly" !! 'Record is marked as readonly';
  }
}

class X::FrozenRecord is Exception is export {
  has Str $.model;
  method message {
    $!model.defined ?? "$!model has been destroyed and is frozen" !! 'Record has been destroyed and is frozen';
  }
}

class X::SoleRecordExceeded is Exception is export {
  has Str $.model;
  method message {
    "Wanted only one " ~ ($!model // 'record');
  }
}

class X::Rollback is Exception is export {
  has Str $.reason;
  method message {
    $!reason.defined ?? "Transaction rolled back: $!reason" !! 'Transaction rolled back';
  }
}

class X::TransactionRequired is Exception is export {
  method message { 'A transaction is required for this operation' }
}

class X::StaleObjectError is Exception is export {
  has Str $.model;
  has Str $.attempted-on = 'save';
  method message {
    my $m = $!model // 'record';
    "Attempted to $!attempted-on a stale object: $m";
  }
}
