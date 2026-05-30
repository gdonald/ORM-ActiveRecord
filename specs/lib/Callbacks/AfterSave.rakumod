use ORM::ActiveRecord::Model;
use Models::Log;

unit module Callbacks::AfterSave;

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-save: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was saved';
    Log.create({:$log});
  }
}

GLOBAL::<Client> := Client;
