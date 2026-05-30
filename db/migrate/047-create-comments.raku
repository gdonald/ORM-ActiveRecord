use ORM::ActiveRecord::Schema::Migration;

class CreateComments is Migration {
  method up {
    self.create-table: 'comments', [
      body              => { :string, limit => 64 },
      commentable_id    => { :integer },
      commentable_type  => { :string, limit => 32 },
    ];
  }

  method down {
    self.drop-table: 'comments';
  }
}
