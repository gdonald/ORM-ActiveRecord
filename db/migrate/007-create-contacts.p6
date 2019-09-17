
use ORM::ActiveRecord::Migration;

class CreateContacts is Migration {
  method up {
    self.create-table: 'contacts', [
      email => { :string, limit => 80 }
    ]
  }

  method down {
    self.drop-table: 'contacts';
  }
}
