use ORM::ActiveRecord::Schema::Migration;

class CreateMeters is Migration {
  method up {
    self.create-table: 'meters', [
      above_zero    => { :integer, null => False, default => 1 },
      at_least_zero => { :integer, null => False, default => 0 },
      below_zero    => { :integer, null => False, default => -1 },
      at_most_zero  => { :integer, null => False, default => 0 },
      balance       => { :decimal, precision => 8, scale => 2, null => False, default => 0 },
    ];
  }

  method down {
    self.drop-table: 'meters';
  }
}
