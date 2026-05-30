use ORM::ActiveRecord::Schema::Migration;

class AddCoauthorToArticles is Migration {
  method up {
    self.add-column: 'articles', :coauthor_id => { :integer };
  }

  method down {
    self.remove-column: 'articles', :coauthor_id;
  }
}
