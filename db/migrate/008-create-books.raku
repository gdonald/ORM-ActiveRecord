
use ORM::ActiveRecord::Migration;

class CreateBooks is Migration {
  method up {
    self.create-table: 'books', [
      title => { :string, limit => 64 },
      pages => { :integer, null => False, default => 0 },
      sentences => { :integer, null => False, default => 0 },
      words => { :integer, null => False, default => 0 },
      periods => { :integer, null => False, default => 0 },
      commas => { :integer, null => False, default => 0 }
    ]
  }

  method down {
    self.drop-table: 'books';
  }
}
