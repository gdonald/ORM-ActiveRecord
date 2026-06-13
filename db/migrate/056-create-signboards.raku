
use ORM::ActiveRecord::Schema::Migration;

class CreateSignboards is Migration {
  method up {
    self.create-table: 'signboards', [
      workshop => { :reference },
      slogan   => { :string, limit => 32 }
    ]
  }

  method down {
    self.drop-table: 'signboards';
  }
}
