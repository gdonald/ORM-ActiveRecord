
use ORM::ActiveRecord::Schema::Migration;

class CreateAccounts is Migration {
  method up {
    self.create-table: 'accounts', [
      name => { :string, limit => 64 },
    ];
  }

  method down {
    self.drop-table: 'accounts';
  }
}
