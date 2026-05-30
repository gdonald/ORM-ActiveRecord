use ORM::ActiveRecord::Model;

unit module Models::Subscription;

class Subscription is Model is export {
  submethod BUILD {
    self.belongs-to: user     => class-name => 'User';
    self.belongs-to: magazine => class-name => 'Magazine';
  }
}

GLOBAL::<Subscription> := Subscription;
