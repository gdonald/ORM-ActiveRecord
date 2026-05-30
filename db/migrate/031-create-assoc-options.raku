
use ORM::ActiveRecord::Schema::Migration;

class CreateAssocOptions is Migration {
  method up {
    # strict-loading: parent + child
    self.create-table: 'slowners', [
      name => { :string, limit => 64 },
    ];
    self.create-table: 'slthings', [
      label      => { :string, limit => 64 },
      slowner_id => { :integer },
    ];

  }

  method down {
    self.drop-table: 'slthings';
    self.drop-table: 'slowners';
  }
}
