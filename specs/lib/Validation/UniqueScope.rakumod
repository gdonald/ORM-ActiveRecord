use ORM::ActiveRecord::Model;

unit module Validation::UniqueScope;

class User is Model is export {
  submethod BUILD {
    self.has-many: subscriptions => class-name => 'Subscription';

    self.validate: 'fname', { :presence }
  }
}

class Magazine is Model is export {
  submethod BUILD {
    self.has-many: subscriptions => class-name => 'Subscription';

    self.validate: 'title', { :presence }
  }
}

class Subscription is Model is export {
  submethod BUILD {
    self.belongs-to: user => class-name => 'User';
    self.belongs-to: magazine => class-name => 'Magazine';

    self.validate: 'user_id', { uniqueness => scope => :magazine_id }
  }
}

GLOBAL::<User>         := User;
GLOBAL::<Magazine>     := Magazine;
GLOBAL::<Subscription> := Subscription;
