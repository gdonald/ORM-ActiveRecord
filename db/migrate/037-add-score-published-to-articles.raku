use ORM::ActiveRecord::Schema::Migration;

class AddScorePublishedToArticles is Migration {
  method up {
    self.add-column: 'articles', :score     => { :integer, default => 0 };
    self.add-column: 'articles', :published => { :boolean, default => False };
  }

  method down {
    self.remove-column: 'articles', :published;
    self.remove-column: 'articles', :score;
  }
}
