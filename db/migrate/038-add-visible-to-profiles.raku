use ORM::ActiveRecord::Schema::Migration;

class AddVisibleToProfiles is Migration {
  method up {
    self.add-column: 'profiles', :visible => { :boolean, default => True };
  }

  method down {
    self.remove-column: 'profiles', :visible;
  }
}
