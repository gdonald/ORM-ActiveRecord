
use ORM::ActiveRecord::Schema::Migration;

class CreateTags is Migration {
  method up {
    self.create-table: 'tags', [
      name => { :string, limit => 40 },
    ]
  }

  method down {
    self.drop-table: 'tags'
  }
}
