
use ORM::ActiveRecord::Schema::Migration;

class CreatePostsTags is Migration {
  method up {
    self.create-table: 'posts_tags', [
      post => { :reference },
      tag  => { :reference },
    ];
    self.add-index: 'posts_tags', <post_id tag_id> => { :unique }
  }

  method down {
    self.drop-table: 'posts_tags';
  }
}
