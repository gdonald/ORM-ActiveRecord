
use ORM::ActiveRecord::Schema::Migration;

class AddAccountToProfiles is Migration {
  method up {
    self.add-column: 'profiles', :account => { :reference };
  }

  method down {
    self.remove-column: 'profiles', :account_id;
  }
}
