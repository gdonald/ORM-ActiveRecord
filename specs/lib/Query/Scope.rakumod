use ORM::ActiveRecord::Model;

unit module Query::Scope;

class Image is Model is export {
  $?CLASS.scope: 'jpgs', -> { $?CLASS.where({ext => 'jpg'}) }

  submethod BUILD {
    self.validate: 'name', { :presence }
    self.validate: 'ext', { :presence, inclusion => { in => <gif jpeg jpg png> } }
  }
}

GLOBAL::<Image> := Image;
