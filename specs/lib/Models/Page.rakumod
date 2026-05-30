use ORM::ActiveRecord::Model;

unit module Models::Page;

class Page is Model is export {
  submethod BUILD {
    self.belongs-to: user => class-name => 'User';

    self.belongs-to: autosave-user => %(
      class-name  => 'User',
      foreign-key => 'user_id',
      autosave    => True,
      validate    => True,
      optional    => True,
    );
  }
}

GLOBAL::<Page> := Page;
