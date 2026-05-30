use ORM::ActiveRecord::Schema::Migration;

class ExtendCounterCache is Migration {
  method up {
    self.add-column: 'users',     :articles_count       => { :integer, null => False, default => 0 };
    self.add-column: 'magazines', :managed_articles_ct  => { :integer, null => False, default => 0 };
    self.add-column: 'articles',  :magazine_id          => { :integer };
  }

  method down {
    self.remove-column: 'articles',  :magazine_id;
    self.remove-column: 'magazines', :managed_articles_ct;
    self.remove-column: 'users',     :articles_count;
  }
}
