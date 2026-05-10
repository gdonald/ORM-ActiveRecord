
use ORM::ActiveRecord::Schema::Migration;

class CreateContracts is Migration {
  method up {
    self.create-table: 'contracts', [
      name => { :string, limit => 64 },
      terms => { :boolean, default => False }
    ]
  }

  method down {
    self.drop-table: 'contracts';
  }
}
