
use ORM::ActiveRecord::Schema::Migration;

class CreateAttachments is Migration {
  method up {
    self.create-table: 'attachments', [
      name => { :string, limit => 80 },
      attachable => { :reference, :polymorphic },
    ]
  }

  method down {
    self.drop-table: 'attachments';
  }
}
