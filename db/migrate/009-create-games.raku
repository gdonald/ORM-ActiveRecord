
use ORM::ActiveRecord::Migration;

class CreateGames is Migration {
  method up {
    self.create-table: 'games', [
      name => { :string, :null },
    ]
  }

  method down {
    self.drop-table: 'games';
  }
}
