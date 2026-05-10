
use ORM::ActiveRecord::Schema::Migration;

class CreateSubscriptions is Migration {
  method up {
    self.create-table: 'subscriptions', [
      user => { :reference }
      magazine => { :reference }
    ];
    self.add-index: 'subscriptions', <user_id magazine_id> => { :unique }
  }

  method down {
    self.drop-table: 'subscriptions';
  }
}
