
use ORM::ActiveRecord::Schema::Migration;

class AddAuthorToArticles is Migration {
  method up {
    self.add-column: 'articles', :author_id => { :integer };
  }

  method down {
    self.remove-column: 'articles', :author_id;
  }
}
