
use ORM::ActiveRecord::Schema::Migration;

class CreateAssocOptions is Migration {
  method up {
    # touch: parent table has updated_at + an extra column to bump
    self.create-table: 'tnshops', [
      name        => { :string, limit => 64 },
      reviewed_at => { :timestamp },
    ];
    self.add-timestamps('tnshops');
    self.create-table: 'tnitems', [
      label      => { :string, limit => 64 },
      tnshop_id  => { :integer },
    ];
    self.add-timestamps('tnitems');

    # strict-loading: parent + child
    self.create-table: 'slowners', [
      name => { :string, limit => 64 },
    ];
    self.create-table: 'slthings', [
      label      => { :string, limit => 64 },
      slowner_id => { :integer },
    ];

    # autosave / validate: parent + child
    self.create-table: 'asparents', [
      name => { :string, limit => 64 },
    ];
    self.create-table: 'aschilds', [
      title       => { :string, limit => 64 },
      asparent_id => { :integer },
    ];

    # through source / source_type / disable_joins
    self.create-table: 'thusers', [
      name => { :string, limit => 64 },
    ];
    self.create-table: 'thmags', [
      title => { :string, limit => 64 },
    ];
    self.create-table: 'thsubs', [
      thuser_id => { :integer },
      thmag_id  => { :integer },
    ];

    # query_constraints: multi-column FK on child
    self.create-table: 'qcorgs', [
      name => { :string, limit => 64 },
    ];
    self.create-table: 'qcdocs', [
      title     => { :string, limit => 64 },
      qcorg_id  => { :integer },
      qcuser_id => { :integer },
    ];
  }

  method down {
    self.drop-table: 'qcdocs';
    self.drop-table: 'qcorgs';
    self.drop-table: 'thsubs';
    self.drop-table: 'thmags';
    self.drop-table: 'thusers';
    self.drop-table: 'aschilds';
    self.drop-table: 'asparents';
    self.drop-table: 'slthings';
    self.drop-table: 'slowners';
    self.drop-table: 'tnitems';
    self.drop-table: 'tnshops';
  }
}
