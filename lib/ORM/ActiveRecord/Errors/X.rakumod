
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

class X::ReadOnlyDatabase is Exception is export {
  has Str $.sql;
  method message {
    my $head = ($!sql // '').lines.first // '';
    "Write query attempted while writes are prevented" ~ ($head ?? ": $head" !! '');
  }
}

class X::ProhibitedShardSwap is Exception is export {
  method message { 'Shard swapping is prohibited in this scope' }
}

class X::ProhibitedReplicaSwap is Exception is export {
  method message { 'Replica role swapping is prohibited in this scope' }
}

class X::StrictLoadingViolationError is Exception is export {
  has Str $.model;
  has Str $.association;
  method message {
    my $m = $!model // 'record';
    my $a = $!association // 'association';
    "$m: '$a' is marked as strict-loading; lazy loading is not allowed";
  }
}

class X::DeleteRestrictionError is Exception is export {
  has Str $.model;
  has Str $.association;
  method message {
    my $m = $!model // 'record';
    my $a = $!association // 'dependent records';
    "Cannot delete $m because of dependent $a";
  }
}
