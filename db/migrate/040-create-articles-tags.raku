use ORM::ActiveRecord::Schema::Migration;

class CreateArticlesTags is Migration {
  method up {
    self.create-table: 'articles_tags', [
      article => { :reference },
      tag     => { :reference },
    ];
    self.add-index: 'articles_tags', <article_id tag_id> => { :unique };
  }

  method down {
    self.drop-table: 'articles_tags';
  }
}
