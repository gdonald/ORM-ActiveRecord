
use ORM::ActiveRecord::Migration;

class CreatePersons is Migration {
  method up {
    self.create-table: 'persons', [
      username => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'persons';
  }
}
