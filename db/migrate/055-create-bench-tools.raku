
use ORM::ActiveRecord::Schema::Migration;

class CreateBenchTools is Migration {
  method up {
    self.create-table: 'bench_tools', [
      workshop => { :reference },
      name     => { :string, limit => 32 },
      level    => { :integer }
    ]
  }

  method down {
    self.drop-table: 'bench_tools';
  }
}
