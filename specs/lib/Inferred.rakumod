use ORM::ActiveRecord::Model;
use Models::Account;
use Models::Picture;

unit module Inferred;

class User is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-many: :pages;
    self.has-one:  :profile;
    self.has-many: :subscriptions;
    self.has-many: magazines => %(through => :subscriptions);
    self.has-one:  account   => %(through => :profile);
  }
}

class Page is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: :user;
    self.belongs-to: author => %(class-name => 'Inferred::User', foreign-key => 'user_id');
    self.belongs-to: writer => %(class => User, foreign-key => 'user_id');
  }
}

class Profile is Model {
  method table-name { 'profiles' }

  submethod BUILD {
    self.belongs-to: :user;
    self.belongs-to: account => %(optional => True);
  }
}

class Magazine is Model {
  method table-name { 'magazines' }
}

class Subscription is Model {
  method table-name { 'subscriptions' }

  submethod BUILD {
    self.belongs-to: :user;
    self.belongs-to: :magazine;
  }
}

class Post is Model {
  method table-name { 'posts' }

  submethod BUILD {
    self.has-and-belongs-to-many: :tags;
    self.has-many: pictures => %(as => 'imageable');
  }
}

class Tag is Model {
  method table-name { 'tags' }

  submethod BUILD {
    self.has-and-belongs-to-many: :posts;
  }
}

class Cart is Model {
  submethod BUILD {
    self.has-many: :cart-tags;
    self.has-many: tags => %(through => :cart-tags);
    self.has-many: :line-items;
    self.has-many: :people;
    self.has-many: :categories;
  }
}

class CartTag is Model {
  submethod BUILD {
    self.belongs-to: :cart;
    self.belongs-to: :tag;
  }
}

class LineItem is Model {
  submethod BUILD {
    self.belongs-to: :cart;
    self.has-many: :line-item-notes;
  }
}

class LineItemNote is Model {
  submethod BUILD {
    self.belongs-to: :line-item;
  }
}

class Person is Model { }

class Category is Model { }

class RoleNamed is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: :manager;
  }
}

class LateOwner is Model {
  method table-name { 'carts' }

  submethod BUILD {
    self.belongs-to: :late-target;
  }
}

my class LateTarget is Model is export { }

class Underscored is Model {
  method table-name { 'carts' }

  submethod BUILD {
    self.has-many: :line_items;
  }
}

class CountedItem is Model { }

class CountedCart is Model {
  method table-name { 'carts' }

  submethod BUILD {
    self.has-many: :counted-items;
  }
}

class ConcurrentItem is Model { }

class ConcurrentCart is Model {
  method table-name { 'carts' }

  submethod BUILD {
    self.has-many: :concurrent-items;
  }
}

GLOBAL::<Inferred> := Inferred;
