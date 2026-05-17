
use ORM::ActiveRecord::Schema::Migration;

class CreateOwnerships is Migration {
  method up {
    self.create-table: 'destroyowners',  [ name => { :string, limit => 64 } ];
    self.create-table: 'deleteowners',   [ name => { :string, limit => 64 } ];
    self.create-table: 'nullifyowners',  [ name => { :string, limit => 64 } ];
    self.create-table: 'resterrowners',  [ name => { :string, limit => 64 } ];
    self.create-table: 'restexcowners',  [ name => { :string, limit => 64 } ];
    self.create-table: 'onedestroyowners', [ name => { :string, limit => 64 } ];
    self.create-table: 'onenullifyowners', [ name => { :string, limit => 64 } ];
    self.create-table: 'onerestexcowners', [ name => { :string, limit => 64 } ];

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
    self.drop-table: 'onerestexcowners';
    self.drop-table: 'onenullifyowners';
    self.drop-table: 'onedestroyowners';
    self.drop-table: 'restexcowners';
    self.drop-table: 'resterrowners';
    self.drop-table: 'nullifyowners';
    self.drop-table: 'deleteowners';
    self.drop-table: 'destroyowners';
  }
}
