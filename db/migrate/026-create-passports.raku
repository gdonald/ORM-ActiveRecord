
use ORM::ActiveRecord::Schema::Migration;

class CreatePassports is Migration {
  method up {
    self.create-table: 'passports', [
      owner_id => { :integer },
      number   => { :string, limit => 32 },
    ];
  }

  method down {
    self.drop-table: 'passports';
  }
}
