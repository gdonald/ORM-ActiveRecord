
use ORM::ActiveRecord::Schema::Migration;

class CreateAssocOptions is Migration {
  method up {
    self.create-table: 'studios', [
      name => { :string, limit => 64 },
    ];
    self.create-table: 'tracks', [
      label     => { :string, limit => 64 },
      studio_id => { :integer },
    ];

  }

  method down {
    self.drop-table: 'tracks';
    self.drop-table: 'studios';
  }
}
