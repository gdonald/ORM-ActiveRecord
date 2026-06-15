
use ORM::ActiveRecord::Support::Utils;

role ModelDiscard is export {
  my %soft-delete-config;

  method soft-deletes(Str:D :$column = 'deleted_at', Bool:D :$default-scope = False) {
    %soft-delete-config{self.WHAT.^name} = { :$column, :$default-scope };
    self;
  }

  method !soft-delete-config-merged {
    my %merged;
    for self.WHAT.^mro.reverse -> $ancestor {
      with %soft-delete-config{$ancestor.^name} -> %defs {
        %merged{.key} = .value for %defs;
      }
    }
    %merged;
  }

  method soft-delete-column(--> Str) {
    self!soft-delete-config-merged<column> // Str;
  }

  method is-soft-delete(--> Bool) {
    self.soft-delete-column.defined;
  }

  method soft-delete-default-scope-column(--> Str) {
    my %cfg = self!soft-delete-config-merged;
    return Str unless %cfg<column>:exists;
    %cfg<default-scope> ?? %cfg<column> !! Str;
  }

  method with-discarded {
    my $column = self.soft-delete-column;
    my $relation = self.all;
    $relation.unscope(where => $column) if $column.defined;
    $relation;
  }

  method kept {
    my $column = self.soft-delete-column;
    return self.all unless $column.defined;
    self.with-discarded.where({ $column => Nil });
  }

  method discarded {
    my $column = self.soft-delete-column;
    return self.all unless $column.defined;
    self.with-discarded.not({ $column => Nil });
  }

  method discard-all {
    my @discarded;
    for self.kept.all -> $record {
      @discarded.push($record) if $record.discard;
    }
    @discarded;
  }

  method undiscard-all {
    my @undiscarded;
    for self.discarded.all -> $record {
      @undiscarded.push($record) if $record.undiscard;
    }
    @undiscarded;
  }

  method is-discarded(--> Bool) {
    my $column = self.WHAT.soft-delete-column;
    return False unless $column.defined;
    self.read-attribute($column).defined;
  }

  method is-kept(--> Bool) {
    !self.is-discarded;
  }

  method discard(--> Bool) {
    my $column = self.WHAT.soft-delete-column;
    return False unless $column.defined;
    return False unless self.id;
    return False if self.is-discarded;
    return False unless self.do-before-discards;

    self.update-column($column, DateTime.now);

    self.do-after-discards;
    True;
  }

  method undiscard(--> Bool) {
    my $column = self.WHAT.soft-delete-column;
    return False unless $column.defined;
    return False unless self.id;
    return False unless self.is-discarded;
    return False unless self.do-before-undiscards;

    self!soft-delete-clear($column);

    self.do-after-undiscards;
    True;
  }

  method !soft-delete-clear(Str:D $column) {
    my $table = self.table-name;
    my @binds;
    my $where-clause;

    if self.WHAT.default-id-locating {
      $where-clause = 'id = ?';
      @binds.push: self.id;
    } else {
      my %where = self.primary-key-where;
      $where-clause = %where.keys.map({ "$_ = ?" }).join(' AND ');
      @binds = %where.values;
    }

    my $stmt = self.db.sanitize-sql-array([
      "UPDATE $table SET $column = NULL WHERE $where-clause", |@binds,
    ]);
    self.db.exec-stmt($stmt);

    self.attrs{$column}    = Nil;
    self.attrs-db{$column} = Nil;
  }
}
