
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Utils;

role ModelBulk is export {
  method destroy-all {
    my $table = Utils.table-name(self);
    my %where;
    DB.shared.delete-records(:$table, :%where);
  }

  method update-all(**@args, *%kw --> Int) {
    self.all.update-all(|@args, |%kw);
  }

  method delete-all(--> Int) {
    self.all.delete-all;
  }

  method destroy-by(Hash:D $conditions --> Int) {
    self.where($conditions).destroy-all;
  }

  method delete-by(Hash:D $conditions --> Int) {
    self.where($conditions).delete-all;
  }

  multi method update-counters(Int:D $id, *%counters --> Int) {
    self.where({ :$id }).update-counters(|%counters);
  }

  multi method update-counters(@ids, *%counters --> Int) {
    self.where({ id => @ids.list }).update-counters(|%counters);
  }

  method !insert-types {
    my $table = Utils.table-name(self);
    my %types;
    for DB.shared.get-fields(:$table) -> $f { %types{$f[0]} = $f[1] }
    %types;
  }

  method insert(%attrs --> Int) {
    self!do-insert([%attrs.item], :skip-conflict)[0] // 0;
  }

  method insert-or-die(%attrs --> Int) {
    self!do-insert([%attrs.item])[0];
  }

  method insert-all(@rows) {
    self!do-insert(@rows.map(*.item).Array, :skip-conflict);
  }

  method insert-all-or-die(@rows) {
    self!do-insert(@rows.map(*.item).Array);
  }

  method !do-insert(@rows, Bool:D :$skip-conflict = False) {
    return () unless @rows.elems;
    my $table = Utils.table-name(self);
    my %types = self!insert-types;
    my @prepared = self.touch-rows-for-insert(@rows);
    DB.shared.insert-records(:$table, :rows(@prepared), :%types, :$skip-conflict);
  }

  method touch-rows-for-insert(@rows) {
    my $now = DateTime.now;
    my $table = Utils.table-name(self);
    my @fields = DB.shared.get-fields(:$table);
    my %names;
    for @fields -> $f { %names{$f[0]} = True }
    my @out;
    for @rows -> %row {
      my %copy = %row;
      %copy<created_at> //= $now if %names<created_at>;
      %copy<updated_at> //= $now if %names<updated_at>;
      @out.push: %copy;
    }
    @out;
  }

  method upsert(%attrs, :@unique-by = ('id',), :@update-cols = () --> Int) {
    self.upsert-all([%attrs.item], :@unique-by, :@update-cols);
  }

  method upsert-all(@rows, :@unique-by = ('id',), :@update-cols = () --> Int) {
    my @items = @rows.map(*.item).Array;
    return 0 unless @items.elems;
    my $table = Utils.table-name(self);
    my %types = self!insert-types;
    my @prepared = self.touch-rows-for-insert(@items);
    DB.shared.upsert-records(:$table, :rows(@prepared), :%types, :@unique-by, :@update-cols);
  }
}
