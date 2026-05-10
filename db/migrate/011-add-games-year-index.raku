
use ORM::ActiveRecord::Schema::Migration;

class AddGamesYearIndex is Migration {
  method up {
    self.add-index: 'games', :year
  }

  method down {
    self.remove-index: 'games', :year;
  }
}
