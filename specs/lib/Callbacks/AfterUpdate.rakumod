use ORM::ActiveRecord::Model;
use Models::Log;

unit module Callbacks::AfterUpdate;

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-update: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was updated';
    Log.create({:$log});
  }
}

GLOBAL::<Client> := Client;
