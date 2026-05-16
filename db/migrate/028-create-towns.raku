
use ORM::ActiveRecord::Schema::Migration;

class CreateTowns is Migration {
  method up {
    self.create-table: 'towns', [
      region_code => { :string, limit => 8 },
      name        => { :string, limit => 64 },
    ];
  }

  method down {
    self.drop-table: 'towns';
  }
}
