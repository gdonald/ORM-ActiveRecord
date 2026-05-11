
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

class X::SoleRecordExceeded is Exception is export {
  has Str $.model;
  method message {
    "Wanted only one " ~ ($!model // 'record');
  }
}
