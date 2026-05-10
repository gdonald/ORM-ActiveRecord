
use ORM::ActiveRecord::Schema::Migration;

class AddGamesYear is Migration {
  method up {
    self.add-column: 'games', :year => { :integer }
  }

  method down {
    self.remove-column: 'games', :year;
  }
}
