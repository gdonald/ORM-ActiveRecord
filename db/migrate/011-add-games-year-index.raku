
use ORM::ActiveRecord::Migration;

class AddGamesYearIndex is Migration {
  method up {
    self.add-index: 'games', :year
  }

  method down {
    self.remove-index: 'games', :year;
  }
}
