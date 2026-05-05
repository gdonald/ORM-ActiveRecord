
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
