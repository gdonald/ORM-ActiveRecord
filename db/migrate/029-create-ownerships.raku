
use ORM::ActiveRecord::Schema::Migration;

class CreateOwnerships is Migration {
  method up {
    self.create-table: 'destroy_owners',  [ name => { :string, limit => 64 } ];
    self.create-table: 'delete_owners',   [ name => { :string, limit => 64 } ];
    self.create-table: 'nullify_owners',  [ name => { :string, limit => 64 } ];
    self.create-table: 'rest_err_owners',  [ name => { :string, limit => 64 } ];
    self.create-table: 'rest_exc_owners',  [ name => { :string, limit => 64 } ];
    self.create-table: 'one_destroy_owners', [ name => { :string, limit => 64 } ];
    self.create-table: 'one_nullify_owners', [ name => { :string, limit => 64 } ];
    self.create-table: 'one_rest_exc_owners', [ name => { :string, limit => 64 } ];

    self.create-table: 'belongings', [
      owner_id => { :integer },
      label    => { :string, limit => 64 },
    ];
    self.create-table: 'singletons', [
      owner_id => { :integer },
      label    => { :string, limit => 64 },
    ];
  }

  method down {
    self.drop-table: 'singletons';
    self.drop-table: 'belongings';
    self.drop-table: 'one_rest_exc_owners';
    self.drop-table: 'one_nullify_owners';
    self.drop-table: 'one_destroy_owners';
    self.drop-table: 'rest_exc_owners';
    self.drop-table: 'rest_err_owners';
    self.drop-table: 'nullify_owners';
    self.drop-table: 'delete_owners';
    self.drop-table: 'destroy_owners';
  }
}
