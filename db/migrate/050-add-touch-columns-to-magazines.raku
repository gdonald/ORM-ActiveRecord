use ORM::ActiveRecord::Schema::Migration;

class AddTouchColumnsToMagazines is Migration {
  method up {
    self.add-timestamps: 'magazines';
    self.add-column: 'magazines', :reviewed_at => { :timestamp };
  }

  method down {
    self.remove-column: 'magazines', :reviewed_at;
    self.remove-timestamps: 'magazines';
  }
}
