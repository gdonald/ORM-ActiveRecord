use ORM::ActiveRecord::Model;

unit module Models::Post;

class Post is Model is export {
  submethod BUILD {
    self.has-and-belongs-to-many: tags => class-name => 'Tag';

    self.has-many: pictures => %(class-name => 'Picture', as => 'imageable');
  }
}

GLOBAL::<Post> := Post;
