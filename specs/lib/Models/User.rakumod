use ORM::ActiveRecord::Model;

unit module Models::User;

role ExtendedArticlesExtension {
  method high-score(Int:D $n) {
    self.records.grep({ .attrs<score> >= $n });
  }
  method by-title {
    self.records.sort({ .attrs<title> });
  }
}

class User is Model is export {
  method fullname {
    (self.attrs<fname> // '') ~ ' ' ~ (self.attrs<lname> // '');
  }

  submethod BUILD {
    self.validate: 'fname', { :presence };

    self.has-many: pages         => class-name => 'Page';
    self.has-many: subscriptions => class-name => 'Subscription';
    self.has-many: magazines     => %(through => :subscriptions, class-name => 'Magazine');
    self.has-one:  profile       => class-name => 'Profile';

    self.has-many: autosave-pages => %(class-name => 'Page', foreign-key => 'user_id');

    self.has-many: published-articles => %(
      class-name  => 'Article',
      foreign-key => 'author_id',
      scope       => -> $q { $q.where({ :published }) },
    );
    self.has-many: top-articles => %(
      class-name  => 'Article',
      foreign-key => 'author_id',
      scope       => -> $q { $q.where({ :published }).order('score').limit(2) },
    );
    self.has-many: by-score => %(
      class-name  => 'Article',
      foreign-key => 'author_id',
      scope       => -> $q, $min { $q.where({ score => $min..* }) },
    );
    self.has-one:  visible-profile => %(
      class-name  => 'Profile',
      foreign-key => 'user_id',
      scope       => -> $q { $q.where({ :visible }) },
    );

    self.has-many: articles => %(
      class-name  => 'Article',
      foreign-key => 'author_id',
      inverse-of  => :scribe,
    );

    self.has-one: passport => %(class-name => 'Passport', foreign-key => 'owner_id');

    self.has-one: account => %(through => :profile);

    self.has-many: pictures => %(class-name => 'Picture', as => 'imageable');

    self.has-many: coauthored-docs => %(
      class-name        => 'Article',
      foreign-key       => 'author_id',
      query-constraints => ['author_id', 'coauthor_id'],
    );

    self.has-many: extended-articles => %(
      class-name  => 'Article',
      foreign-key => 'author_id',
      extension   => ExtendedArticlesExtension,
    );
    self.has-many: comments => %(
      class-name => 'Comment',
      as         => 'commentable',
    );

    self.has-many: subscribed-mags => %(
      class-name => 'Magazine',
      through    => :subscriptions,
      source     => :magazine,
    );
    self.has-many: dj-mags => %(
      class-name    => 'Magazine',
      through       => :subscriptions,
      source        => :magazine,
      disable-joins => True,
    );
  }
}

GLOBAL::<User> := User;
