
use ORM::ActiveRecord::Schema::Migration;

class CreatePhase8Validations is Migration {
  method up {
    self.create-table: 'phevents', [
      name       => { :string, limit => 64 },
      score      => { :integer, null => False, default => 0 },
      max_score  => { :integer, null => False, default => 0 },
      starts_at  => { :datetime },
      ends_at    => { :datetime },
    ];

    self.create-table: 'phlibraries', [
      name => { :string, limit => 64 },
    ];

    self.create-table: 'phbooks', [
      title         => { :string, limit => 64 },
      phlibrary_id  => { :integer },
    ];
  }

  method down {
    self.drop-table: 'phbooks';
    self.drop-table: 'phlibraries';
    self.drop-table: 'phevents';
  }
}
