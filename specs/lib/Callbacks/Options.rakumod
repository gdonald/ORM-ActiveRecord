use ORM::ActiveRecord::Model;

unit module Callbacks::Options;

our @events is export = ();

class Client is Model is export {
  has Bool $.skip-it is rw = False;

  submethod BUILD {
    self.validate: 'email', { :presence };

    # method-name callback (Str handler)
    self.before-save: 'note-save';

    # multiple callbacks fire in declaration order
    self.after-save: -> { @events.push: 'after-1' };
    self.after-save: -> { @events.push: 'after-2' };

    # prepend: inserts at front of chain (runs first)
    self.after-save: 'prepended-after', :prepend;

    # conditional with Block
    self.after-save: -> { @events.push: 'maybe-block' }, :if(-> { self.email.chars > 3 });
    self.after-save: -> { @events.push: 'never-block' }, :unless(-> { True });

    # conditional with Str method name
    self.after-save: -> { @events.push: 'should-skip' }, :if('skip-it');

    # conditional with Array (all must be true)
    self.after-save: -> { @events.push: 'both-conds' },
      :if(['email-long', -> { True }]);

    # halt the chain by returning False
    self.before-update: -> { False };
  }

  method note-save     { @events.push: 'before-save-method'; True }
  method prepended-after { @events.push: 'prepended-after-method' }
  method email-long(--> Bool) { self.email.chars > 3 }
}

GLOBAL::<Client> := Client;
