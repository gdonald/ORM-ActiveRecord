use ORM::ActiveRecord::Model;

unit module Models::Article;

class Article is Model is export {
  submethod BUILD {
    self.belongs-to: author => %(
      class-name  => 'User',
      foreign-key => 'author_id',
      optional    => True,
    );
    self.belongs-to: active-author => %(
      class-name  => 'User',
      foreign-key => 'author_id',
      optional    => True,
      scope       => -> $q { $q.where({ is_active => True }) },
    );
    self.belongs-to: counter-author => %(
      class-name    => 'User',
      foreign-key   => 'author_id',
      counter-cache => True,
      optional      => True,
    );
    self.belongs-to: editor-magazine => %(
      class-name    => 'Magazine',
      foreign-key   => 'magazine_id',
      counter-cache => 'managed_articles_ct',
      optional      => True,
    );
    self.belongs-to: touch-magazine => %(
      class-name  => 'Magazine',
      foreign-key => 'magazine_id',
      touch       => 'reviewed_at',
      optional    => True,
    );
    self.belongs-to: scribe => %(
      class-name  => 'User',
      foreign-key => 'author_id',
      optional    => True,
    );
    self.has-and-belongs-to-many: hot-tags => %(
      class-name => 'Tag',
      join-table => 'articles_tags',
      scope      => -> $q { $q.where({ :hot }) },
    );
  }
}

GLOBAL::<Article> := Article;
