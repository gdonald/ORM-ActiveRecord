
use ORM::ActiveRecord::Schema::Migration;

class CreateDiscardFixtures is Migration {
  method up {
    self.create-table: 'notices', [
      name       => { :string, limit => 64 },
      deleted_at => { :datetime },
    ];

    self.create-table: 'parcels', [
      name          => { :string, limit => 64 },
      discarded_at  => { :datetime },
    ];
  }

  method down {
    self.drop-table: 'notices';
    self.drop-table: 'parcels';
  }
}
