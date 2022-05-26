
use ORM::ActiveRecord::Migration;

class CreateMagazines is Migration {
  method up {
    self.create-table: 'magazines', [
      title => { :string, limit => 80 },
    ]
  }

  method down {
    self.drop-table: 'magazines'
  }
}