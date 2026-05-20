
use ORM::ActiveRecord::Schema::Migration;

class CreateCollectionProxy is Migration {
  method up {
    self.create-table: 'cpauthors', [
      name => { :string, limit => 64 },
    ];

    self.create-table: 'cpposts', [
      title       => { :string, limit => 64 },
      body        => { :string, limit => 64 },
      score       => { :integer, default => 0 },
      cpauthor_id => { :integer },
    ];

    self.create-table: 'cpcomments', [
      body              => { :string, limit => 64 },
      commentable_id    => { :integer },
      commentable_type  => { :string, limit => 32 },
    ];
  }

  method down {
    self.drop-table: 'cpcomments';
    self.drop-table: 'cpposts';
    self.drop-table: 'cpauthors';
  }
}
