use ORM::ActiveRecord::Model;

unit module Models::Profile;

class Profile is Model is export {
  submethod BUILD {
    self.validate: 'bio', { :presence };

    self.belongs-to: user    => class-name => 'User';
    self.belongs-to: account => %(class-name => 'Account', optional => True);
  }
}

GLOBAL::<Profile> := Profile;
