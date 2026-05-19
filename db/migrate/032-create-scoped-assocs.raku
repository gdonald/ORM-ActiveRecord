
use ORM::ActiveRecord::Schema::Migration;

class CreateScopedAssocs is Migration {
  method up {
    self.create-table: 'scauthors', [
      name      => { :string, limit => 64 },
      is_active => { :boolean, default => True },
    ];

    self.create-table: 'scarticles', [
      title       => { :string, limit => 64 },
      score       => { :integer, default => 0 },
      published   => { :boolean, default => False },
      scauthor_id => { :integer },
    ];

    self.create-table: 'scprofiles', [
      bio         => { :string, limit => 64 },
      visible     => { :boolean, default => True },
      scauthor_id => { :integer },
    ];

    self.create-table: 'sctags', [
      name => { :string, limit => 32 },
      hot  => { :boolean, default => False },
    ];

    self.create-table: 'scarticles_sctags', [
      scarticle_id => { :integer },
      sctag_id     => { :integer },
    ];
  }

  method down {
    self.drop-table: 'scarticles_sctags';
    self.drop-table: 'sctags';
    self.drop-table: 'scprofiles';
    self.drop-table: 'scarticles';
    self.drop-table: 'scauthors';
  }
}
