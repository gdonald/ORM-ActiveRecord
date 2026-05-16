
use ORM::ActiveRecord::Schema::Migration;

class CreateEmployees is Migration {
  method up {
    self.create-table: 'employees', [
      name => { :string, limit => 64 },
      manager_id => { :integer },
    ]
  }

  method down {
    self.drop-table: 'employees';
  }
}
