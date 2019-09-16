
use ORM::ActiveRecord::Migration;

class CreateImages is Migration {
  method up {
    self.create-table: 'images', [
      format => { :string, limit => 4 }
    ]
  }

  method down {
    self.drop-table: 'images';
  }
}
