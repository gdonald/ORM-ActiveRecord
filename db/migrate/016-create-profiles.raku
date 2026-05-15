
use ORM::ActiveRecord::Schema::Migration;

class CreateProfiles is Migration {
  method up {
    self.create-table: 'profiles', [
      user => { :reference },
      bio  => { :text },
    ];
    self.add-index: 'profiles', :user_id;
  }

  method down {
    self.drop-table: 'profiles';
  }
}
