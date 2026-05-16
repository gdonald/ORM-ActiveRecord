
use ORM::ActiveRecord::Schema::Migration;

class CreateRegions is Migration {
  method up {
    self.create-table: 'regions', [
      code => { :string, limit => 8 },
      name => { :string, limit => 64 },
    ];
  }

  method down {
    self.drop-table: 'regions';
  }
}
