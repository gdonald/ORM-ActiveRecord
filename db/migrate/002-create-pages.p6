
use ORM::ActiveRecord::Migration;

class CreatePages is Migration {
  method up {
    self.create-table: 'pages', [
      user => { :reference },
      name => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'pages';
  }
}
