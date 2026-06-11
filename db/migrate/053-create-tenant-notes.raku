
use ORM::ActiveRecord::Schema::Migration;

class CreateTenantNotes is Migration {
  method up {
    self.create-table: 'tenant_notes', [
      tenant_id => { :integer },
      id        => { :integer },
      body      => { :string, limit => 32 },
    ], id => False, primary-key => ['tenant_id', 'id'];
  }

  method down {
    self.drop-table: 'tenant_notes';
  }
}
