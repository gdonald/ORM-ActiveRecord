
use ORM::ActiveRecord::Schema::Migration;

class CreatePosts is Migration {
  method up {
    self.create-table: 'posts', [
      title => { :string, limit => 80 },
    ]
  }

  method down {
    self.drop-table: 'posts'
  }
}
