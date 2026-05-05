use ORM::ActiveRecord::Migration;

class CreateArticles is Migration {
  method up {
    self.create-table: 'articles', [
      title => { :string, limit => 64 },
      body  => { :text },
    ];
    self.add-timestamps: 'articles';
  }

  method down {
    self.drop-table: 'articles';
  }
}
