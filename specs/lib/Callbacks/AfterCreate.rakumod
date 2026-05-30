use ORM::ActiveRecord::Model;
use Models::Log;

unit module Callbacks::AfterCreate;

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-create: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was created';
    Log.create({:$log});
  }
}

GLOBAL::<Client> := Client;
