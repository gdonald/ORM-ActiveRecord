
use ORM::ActiveRecord::DB;

role QueryBulk is export {
  method touch-all(*@names --> Int) {
    return 0 if self.is-none-value;
    my $count = 0;
    for self.all -> $obj {
      $obj.touch(|@names);
      $count++;
    }
    $count;
  }

  method update-all(*@args, *%kw --> Int) {
    return 0 if self.is-none-value;
    my %attrs = @args.elems && @args[0] ~~ Hash ?? @args[0].Hash !! %kw;
    die 'update-all: no attributes supplied' unless %attrs.elems;
    my %types = self.fields-of.map({ .name => .type }).Hash;
    my @or-groups = self.or-groups-payload;
    DB.shared.update-records(
      table => self.table-of, :%attrs, :%types,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
    );
  }

  method delete-all(--> Int) {
    return 0 if self.is-none-value;
    DB.shared.delete-records(
      table => self.table-of,
      where => self.where-values, where-not => self.where-not-values,
    );
  }

  method destroy-all(--> Int) {
    return 0 if self.is-none-value;
    my $count = 0;
    for self.all -> $obj {
      $obj.destroy;
      $count++;
    }
    $count;
  }

  method update-counters(*@args, *%kw --> Int) {
    return 0 if self.is-none-value;
    my %counters = @args.elems && @args[0] ~~ Hash ?? @args[0].Hash !! %kw;
    die 'update-counters: no counters supplied' unless %counters.elems;
    my @or-groups = self.or-groups-payload;
    DB.shared.update-counter-records(
      table => self.table-of, :%counters,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
    );
  }
}
