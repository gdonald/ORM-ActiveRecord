
use ORM::ActiveRecord::Migration;

class CreateClients is Migration {
  method up {
    self.create-table: 'clients', [
      email => { :string, limit => 80 }
    ];
    self.add-index: 'clients', email => { :unique }
  }

  method down {
    self.drop-table: 'clients';
  }
}
