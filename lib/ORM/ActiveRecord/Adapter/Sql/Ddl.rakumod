
role SqlDdl is export {
  method ddl-drop-table(Str:D $table) {
    self.exec("DROP TABLE $table");
  }

  # Drop every table the adapter can see. Adapters override to disable FK
  # checks for the duration of the drops so order does not matter.
  method ddl-drop-all-tables(--> List) {
    my @tables = self.get-table-names.list;
    self.ddl-drop-table($_) for @tables;
    @tables;
  }

  method ddl-remove-column(Str:D $table, $field) {
    self.exec("ALTER TABLE $table DROP COLUMN $field");
  }

  method ddl-remove-timestamps(Str:D $table) {
    self.exec("ALTER TABLE $table DROP COLUMN created_at, DROP COLUMN updated_at");
  }

  method ddl-add-index(Str:D $table, Str:D :$name, Str:D :$columns, Bool:D :$unique = False) {
    my $u = $unique ?? 'UNIQUE ' !! '';
    self.exec("CREATE {$u}INDEX $name ON $table ($columns)");
  }

  method ddl-remove-index(Str:D :$name) {
    self.exec("DROP INDEX $name");
  }
}
