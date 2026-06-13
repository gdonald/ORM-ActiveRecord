
use ORM::ActiveRecord::Schema::Migration;

class CreateWorkshops is Migration {
  method up {
    self.create-table: 'workshops', [
      name => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'workshops';
  }
}
