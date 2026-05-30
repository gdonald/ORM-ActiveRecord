use ORM::ActiveRecord::Model;

unit module Models::Magazine;

class Magazine is Model is export {
  submethod BUILD {
    self.has-many: subscriptions => class-name => 'Subscription';
    self.has-many: users => %(
      class-name => 'User',
      through    => :subscriptions,
    );
  }
}

GLOBAL::<Magazine> := Magazine;
