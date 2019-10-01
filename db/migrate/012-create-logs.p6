
use ORM::ActiveRecord::Migration;

class CreateLogs is Migration {
  method up {
    self.create-table: 'logs', [
      log => { :text }
    ]
  }

  method down {
    self.drop-table: 'logs';
  }
}
