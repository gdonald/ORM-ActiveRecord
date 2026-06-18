
use ORM::ActiveRecord::DB;

# Clears the database between tests with a selectable strategy:
#
#   deletion    — DELETE FROM every table (default, fast on SQLite)
#   truncation  — TRUNCATE every table (RESTART IDENTITY / reset sequences)
#   transaction — run a block inside a transaction and roll it back
#
#   my $cleaner = DatabaseCleaner.new;
#   $cleaner.clean;                              # deletion
#   $cleaner.clean(strategy => 'truncation');
#   $cleaner.cleaning({ ... });                  # transaction-wrapped
class DatabaseCleaner is export {
  has @.except = <migrations>;

  method !adapter { DB.shared.adapter }

  method !tables {
    self!adapter.get-table-names.list.grep({ $_ ne any(@!except) });
  }

  method !adapter-kind(--> Str) {
    given self!adapter.^name {
      when /Pg/    { 'pg' }
      when /MySql/ { 'mysql' }
      default      { 'sqlite' }
    }
  }

  method clean(Str:D :$strategy = 'deletion') {
    given $strategy {
      when 'deletion'    { self!delete-all }
      when 'truncation'  { self!truncate-all }
      when 'transaction' { }   # isolation comes from cleaning(), not clean()
      default { die "database cleaner: unknown strategy '$strategy'" }
    }
  }

  method cleaning(&block, Str:D :$strategy = 'transaction') {
    if $strategy eq 'transaction' {
      my $adapter = self!adapter;
      $adapter.open-transaction;
      LEAVE { $adapter.force-rollback }
      return block();
    }

    LEAVE { self.clean(:$strategy) }
    block();
  }

  method !delete-all {
    my $adapter = self!adapter;
    for self!tables -> $table { try $adapter.exec("DELETE FROM $table") }
  }

  method !truncate-all {
    my $adapter = self!adapter;
    my @tables  = self!tables;
    return unless @tables;

    given self!adapter-kind {
      when 'pg' {
        $adapter.exec("TRUNCATE {@tables.join(', ')} RESTART IDENTITY CASCADE");
      }
      when 'mysql' {
        $adapter.exec('SET FOREIGN_KEY_CHECKS = 0');
        $adapter.exec("TRUNCATE TABLE $_") for @tables;
        $adapter.exec('SET FOREIGN_KEY_CHECKS = 1');
      }
      default {
        $adapter.exec("DELETE FROM $_") for @tables;
        try $adapter.exec('DELETE FROM sqlite_sequence');
      }
    }
  }
}
