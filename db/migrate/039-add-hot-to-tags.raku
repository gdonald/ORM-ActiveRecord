use ORM::ActiveRecord::Schema::Migration;

class AddHotToTags is Migration {
  method up {
    self.add-column: 'tags', :hot => { :boolean, default => False };
  }

  method down {
    self.remove-column: 'tags', :hot;
  }
}
