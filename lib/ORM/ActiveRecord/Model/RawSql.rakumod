
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Utils;

role ModelRawSql is export {
  multi method find-by-sql(@parts) {
    self!do-find-by-sql(@parts);
  }

  multi method find-by-sql(Str:D $sql, *@binds) {
    self!do-find-by-sql([$sql, |@binds]);
  }

  method !do-find-by-sql(@parts) {
    my $stmt = DB.shared.sanitize-sql(@parts);
    my @rows = DB.shared.exec-stmt-hash($stmt);
    my $table = Utils.table-name(self);
    my @fields = DB.shared.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
    my %field-types = @fields.map({ .name => .type });

    my @objects;
    for @rows -> %row {
      my %attrs;
      for %row.kv -> $k, $v {
        if %field-types{$k}:exists {
          %attrs{$k} = DB.shared.coerce-read($v, type => %field-types{$k});
        } else {
          %attrs{$k} = $v;
        }
      }
      my $id = (%attrs<id> // 0).Int;
      my $obj = self.new(:$id, :record({ attrs => %attrs }));
      @objects.push: $obj;
    }
    @objects;
  }

  multi method select-all(@parts) {
    self!do-select-all(@parts);
  }

  multi method select-all(Str:D $sql, *@binds) {
    self!do-select-all([$sql, |@binds]);
  }

  method !do-select-all(@parts) {
    my $stmt = DB.shared.sanitize-sql(@parts);
    DB.shared.exec-stmt-hash($stmt);
  }
}
