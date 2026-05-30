
use ORM::ActiveRecord::Schema::Migration;

class CreatePhase8ValidatorOptions is Migration {
  method up {
    self.create-table: 'members', [
      username  => { :string, limit => 64 },
      tenant_id => { :integer, default => 0 },
      is_active => { :boolean, default => True },
    ];
  }

  method down {
    self.drop-table: 'members';
  }
}
