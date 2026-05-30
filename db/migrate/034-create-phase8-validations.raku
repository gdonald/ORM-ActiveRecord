
use ORM::ActiveRecord::Schema::Migration;

class CreatePhase8Validations is Migration {
  method up {
    self.create-table: 'concerts', [
      name       => { :string, limit => 64 },
      score      => { :integer, null => False, default => 0 },
      max_score  => { :integer, null => False, default => 0 },
      starts_at  => { :datetime },
      ends_at    => { :datetime },
    ];

    self.create-table: 'archives', [
      name => { :string, limit => 64 },
    ];

    self.create-table: 'manuals', [
      title      => { :string, limit => 64 },
      archive_id => { :integer },
    ];
  }

  method down {
    self.drop-table: 'manuals';
    self.drop-table: 'archives';
    self.drop-table: 'concerts';
  }
}
