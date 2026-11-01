use ORM::ActiveRecord::Schema::Migration;

class CreateCartsAndLineItems is Migration {
  method up {
    self.create-table: 'carts', [
      name => { :string, limit => 64 },
    ];

    self.create-table: 'line_items', [
      cart  => { :reference },
      name  => { :string, limit => 64 },
    ];

    self.create-table: 'line_item_notes', [
      line_item => { :reference },
      body      => { :string, limit => 64 },
    ];

    self.create-table: 'cart_tags', [
      cart => { :reference },
      tag  => { :reference },
    ];
  }

  method down {
    self.drop-table: 'cart_tags';
    self.drop-table: 'line_item_notes';
    self.drop-table: 'line_items';
    self.drop-table: 'carts';
  }
}
