use ORM::ActiveRecord::Model;

unit module Callbacks::SkipSetTerminator;

our @events is export = ();

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-save: -> { @events.push: 'b1' }, :tag<b1>;
    self.before-save: -> { @events.push: 'b2' }, :tag<b2>;
    self.before-save: -> { @events.push: 'b3' }, :tag<b3>;
  }
}

GLOBAL::<Client> := Client;
