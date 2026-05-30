use ORM::ActiveRecord::Schema::Migration;

class AddIsactiveToUsers is Migration {
  method up {
    self.add-column: 'users', :is_active => { :boolean, default => True };
  }

  method down {
    self.remove-column: 'users', :is_active;
  }
}
