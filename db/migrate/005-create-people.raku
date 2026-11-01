
use ORM::ActiveRecord::Schema::Migration;

class CreatePeople is Migration {
  method up {
    self.create-table: 'people', [
      username => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'people';
  }
}
