
use ORM::ActiveRecord::Schema::Migration;

class CreateCounterCache is Migration {
  method up {
    self.create-table: 'ccshops', [
      name          => { :string, limit => 64 },
      ccbooks_count => { :integer, null => False, default => 0 },
    ];

    self.create-table: 'ccteams', [
      name             => { :string, limit => 64 },
      managed_books_ct => { :integer, null => False, default => 0 },
    ];

    self.create-table: 'ccbooks', [
      title     => { :string, limit => 64 },
      ccshop_id => { :integer },
      ccteam_id => { :integer },
    ];
  }

  method down {
    self.drop-table: 'ccbooks';
    self.drop-table: 'ccteams';
    self.drop-table: 'ccshops';
  }
}
