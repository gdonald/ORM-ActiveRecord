
use ORM::ActiveRecord::Schema::Migration;

class Schema is Migration {
  method up {
    self.create-table: 'accounts', [
      name => { :text },
    ];

    self.create-table: 'archives', [
      name => { :text },
    ];

    self.create-table: 'articles', [
      title       => { :text },
      body        => { :text },
      created_at  => { :datetime },
      updated_at  => { :datetime },
      author_id   => { :integer },
      score       => { :integer },
      published   => { :boolean },
      magazine_id => { :integer },
      coauthor_id => { :integer },
    ];

    self.create-table: 'articles_tags', [
      article_id => { :integer, references => 'articles' },
      tag_id     => { :integer, references => 'tags' },
    ];
    self.add-index: 'articles_tags', <article_id tag_id>, :unique;

    self.create-table: 'attachments', [
      name            => { :text },
      attachable_id   => { :integer },
      attachable_type => { :text },
    ];

    self.create-table: 'belongings', [
      owner_id => { :integer },
      label    => { :text },
    ];

    self.create-table: 'bench_tools', [
      workshop_id => { :integer, references => 'workshops' },
      name        => { :text },
      level       => { :integer },
    ];

    self.create-table: 'books', [
      title     => { :text },
      pages     => { :integer },
      sentences => { :integer },
      words     => { :integer },
      periods   => { :integer },
      commas    => { :integer },
    ];

    self.create-table: 'clients', [
      email => { :text },
    ];
    self.add-index: 'clients', 'email', :unique;

    self.create-table: 'comments', [
      body             => { :text },
      commentable_id   => { :integer },
      commentable_type => { :text },
    ];

    self.create-table: 'concerts', [
      name      => { :text },
      score     => { :integer },
      max_score => { :integer },
      starts_at => { :datetime },
      ends_at   => { :datetime },
    ];

    self.create-table: 'contacts', [
      email => { :text },
      fname => { :text },
      lname => { :text },
    ];

    self.create-table: 'contracts', [
      name  => { :text },
      terms => { :boolean },
    ];

    self.create-table: 'delete_owners', [
      name => { :text },
    ];

    self.create-table: 'destroy_owners', [
      name => { :text },
    ];

    self.create-table: 'employees', [
      name       => { :text },
      manager_id => { :integer },
    ];

    self.create-table: 'games', [
      name => { :text },
      year => { :integer },
    ];
    self.add-index: 'games', 'year';

    self.create-table: 'images', [
      name => { :text },
      ext  => { :text },
    ];

    self.create-table: 'logs', [
      log => { :text },
    ];

    self.create-table: 'magazines', [
      title               => { :text },
      managed_articles_ct => { :integer },
      created_at          => { :datetime },
      updated_at          => { :datetime },
      reviewed_at         => { :datetime },
    ];

    self.create-table: 'manuals', [
      title      => { :text },
      archive_id => { :integer },
    ];

    self.create-table: 'members', [
      username  => { :text },
      tenant_id => { :integer },
      is_active => { :boolean },
    ];

    self.create-table: 'notices', [
      name       => { :text },
      deleted_at => { :datetime },
    ];

    self.create-table: 'nullify_owners', [
      name => { :text },
    ];

    self.create-table: 'one_destroy_owners', [
      name => { :text },
    ];

    self.create-table: 'one_nullify_owners', [
      name => { :text },
    ];

    self.create-table: 'one_rest_exc_owners', [
      name => { :text },
    ];

    self.create-table: 'pages', [
      user_id => { :integer, references => 'users' },
      name    => { :text },
    ];

    self.create-table: 'parcels', [
      name         => { :text },
      discarded_at => { :datetime },
    ];

    self.create-table: 'passports', [
      owner_id => { :integer },
      number   => { :text },
    ];

    self.create-table: 'persons', [
      username => { :text },
    ];

    self.create-table: 'pictures', [
      name           => { :text },
      imageable_id   => { :integer },
      imageable_type => { :text },
    ];

    self.create-table: 'posts', [
      title => { :text },
    ];

    self.create-table: 'posts_tags', [
      post_id => { :integer, references => 'posts' },
      tag_id  => { :integer, references => 'tags' },
    ];
    self.add-index: 'posts_tags', <post_id tag_id>, :unique;

    self.create-table: 'profiles', [
      user_id    => { :integer, references => 'users' },
      bio        => { :text },
      account_id => { :integer },
      visible    => { :boolean },
    ];
    self.add-index: 'profiles', 'user_id';

    self.create-table: 'regions', [
      code => { :text },
      name => { :text },
    ];

    self.create-table: 'rest_err_owners', [
      name => { :text },
    ];

    self.create-table: 'rest_exc_owners', [
      name => { :text },
    ];

    self.create-table: 'shop_widgets', [
      shop_id  => { :integer },
      name     => { :text },
      quantity => { :integer },
    ];

    self.create-table: 'signboards', [
      workshop_id => { :integer, references => 'workshops' },
      slogan      => { :text },
    ];

    self.create-table: 'singletons', [
      owner_id => { :integer },
      label    => { :text },
    ];

    self.create-table: 'studios', [
      name => { :text },
    ];

    self.create-table: 'subscriptions', [
      user_id     => { :integer, references => 'users' },
      magazine_id => { :integer, references => 'magazines' },
    ];
    self.add-index: 'subscriptions', <user_id magazine_id>, :unique;

    self.create-table: 'tags', [
      name => { :text },
      hot  => { :boolean },
    ];

    self.create-table: 'tenant_notes', [
      tenant_id => { :integer },
      body      => { :text },
    ];

    self.create-table: 'towns', [
      region_code => { :text },
      name        => { :text },
    ];

    self.create-table: 'tracks', [
      label     => { :text },
      studio_id => { :integer },
    ];

    self.create-table: 'users', [
      fname          => { :text },
      lname          => { :text },
      is_active      => { :boolean },
      articles_count => { :integer },
    ];

    self.create-table: 'workshops', [
      name => { :text },
    ];
  }

  method down {
    self.drop-table: 'workshops';
    self.drop-table: 'users';
    self.drop-table: 'tracks';
    self.drop-table: 'towns';
    self.drop-table: 'tenant_notes';
    self.drop-table: 'tags';
    self.drop-table: 'subscriptions';
    self.drop-table: 'studios';
    self.drop-table: 'singletons';
    self.drop-table: 'signboards';
    self.drop-table: 'shop_widgets';
    self.drop-table: 'rest_exc_owners';
    self.drop-table: 'rest_err_owners';
    self.drop-table: 'regions';
    self.drop-table: 'profiles';
    self.drop-table: 'posts_tags';
    self.drop-table: 'posts';
    self.drop-table: 'pictures';
    self.drop-table: 'persons';
    self.drop-table: 'passports';
    self.drop-table: 'parcels';
    self.drop-table: 'pages';
    self.drop-table: 'one_rest_exc_owners';
    self.drop-table: 'one_nullify_owners';
    self.drop-table: 'one_destroy_owners';
    self.drop-table: 'nullify_owners';
    self.drop-table: 'notices';
    self.drop-table: 'members';
    self.drop-table: 'manuals';
    self.drop-table: 'magazines';
    self.drop-table: 'logs';
    self.drop-table: 'images';
    self.drop-table: 'games';
    self.drop-table: 'employees';
    self.drop-table: 'destroy_owners';
    self.drop-table: 'delete_owners';
    self.drop-table: 'contracts';
    self.drop-table: 'contacts';
    self.drop-table: 'concerts';
    self.drop-table: 'comments';
    self.drop-table: 'clients';
    self.drop-table: 'books';
    self.drop-table: 'bench_tools';
    self.drop-table: 'belongings';
    self.drop-table: 'attachments';
    self.drop-table: 'articles_tags';
    self.drop-table: 'articles';
    self.drop-table: 'archives';
    self.drop-table: 'accounts';
  }

  method versions { <001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016 017 018 019 020 021 022 023 024 025 026 027 028 029 031 034 035 036 037 038 039 040 041 042 043 044 045 046 047 048 049 050 051 052 053 054 055 056 057> }
}
