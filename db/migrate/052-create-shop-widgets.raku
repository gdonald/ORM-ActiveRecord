
use ORM::ActiveRecord::Schema::Migration;

class CreateShopWidgets is Migration {
  method up {
    self.create-table: 'shop_widgets', [
      shop_id  => { :integer },
      id       => { :integer },
      name     => { :string, limit => 32 },
      quantity => { :integer },
    ], id => False, primary-key => ['shop_id', 'id'];
  }

  method down {
    self.drop-table: 'shop_widgets';
  }
}
