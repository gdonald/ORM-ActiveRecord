
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

  method find-by-sql-async(|args) {
    my $name = self.connection-name;

    start {
      my $pool = DB.shared(name => $name).pool;
      my $conn = $pool.checkout;
      LEAVE $pool.checkin($conn);

      my $*AR-DB-OVERRIDE = DB.new(:adapter($conn), :$name);
      my @objects = self.find-by-sql(|args);

      my $shared = DB.shared(name => $name);
      .rebind-db($shared) for @objects;

      @objects;
    }
  }

  method !do-find-by-sql(@parts) {
    my $stmt = self.db.sanitize-sql(@parts);
    my @rows = self.db.exec-stmt-hash($stmt);
    my $table = Utils.table-name(self);
    my @fields = self.db.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
    my %field-types = @fields.map({ .name => .type });

    my @objects;
    for @rows -> %row {
      my %attrs;
      for %row.kv -> $k, $v {
        if %field-types{$k}:exists {
          %attrs{$k} = self.db.coerce-read($v, type => %field-types{$k});
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
    my $stmt = self.db.sanitize-sql(@parts);
    self.db.exec-stmt-hash($stmt);
  }
}
