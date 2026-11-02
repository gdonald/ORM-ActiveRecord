use ORM::ActiveRecord::Schema::Migration;

class CreateGuardiansAndWards is Migration {
  method up {
    self.create-table: 'guardians', [
      name => { :string, limit => 64 },
    ];

    self.create-table: 'wards', [
      name        => { :string, limit => 64 },
      guardian_id => { :integer, references => 'guardians', on-delete => 'nullify' },
      score       => { :integer },
      tier        => { :integer, null => False, default => 3 },
      slot        => { :integer, null => False },
      code        => { :string, limit => 64, null => False },
      nickname    => { :string, limit => 64 },
    ];
  }

  method down {
    self.drop-table: 'wards';
    self.drop-table: 'guardians';
  }
}
