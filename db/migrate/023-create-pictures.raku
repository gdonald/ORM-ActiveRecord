
use ORM::ActiveRecord::Schema::Migration;

class CreatePictures is Migration {
  method up {
    self.create-table: 'pictures', [
      name => { :string, limit => 80 },
      imageable => { :reference, :polymorphic },
    ]
  }

  method down {
    self.drop-table: 'pictures';
  }
}
