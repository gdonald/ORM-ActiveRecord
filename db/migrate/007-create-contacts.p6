
use ORM::ActiveRecord::Migration;

class CreateContacts is Migration {
  method up {
    self.create-table: 'contacts', [
      email => { :string, limit => 80 },
      fname => { :string, limit => 32 },
      lname => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'contacts';
  }
}
