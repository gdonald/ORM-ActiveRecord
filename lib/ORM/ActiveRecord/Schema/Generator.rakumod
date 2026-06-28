
# File generators behind `active-record generate` / `active-record destroy`. Render methods are pure
# (string in, string out) so they test without touching disk; the generate- /
# destroy- methods write or remove the rendered files under the configured root.

class Generator is export {
  has Str $.root           = '.';
  has Str $.models-dir     = 'app/models';
  has Str $.validators-dir = 'app/validators';
  has Str $.migrate-dir    = 'db/migrate';
  has Str $.stamp;

  my @REFERENCE-TYPES  = <references reference belongs_to belongs-to ref>;
  my @MODIFIER-KEYWORDS = <uniq unique index>;

  method classize(Str:D $name --> Str) {
    $name.split(/<[_\-\s]>+/).grep(*.chars).map({ .chars > 1 ?? .substr(0, 1).uc ~ .substr(1) !! .uc }).join;
  }

  method kebabize(Str:D $name --> Str) {
    $name
      .subst(/<[_\s]>+/, '-', :g)
      .subst(/(<[a..z0..9]>)(<[A..Z]>)/, { "$0-$1" }, :g)
      .lc;
  }

  method tableize(Str:D $name --> Str) {
    self.classize($name).subst(/(<[a..z0..9]>)(<[A..Z]>)/, { "$0_$1" }, :g).lc ~ 's';
  }

  method parse-field(Str:D $token --> Hash) {
    my @parts = $token.split(':');
    my $name  = @parts[0];
    my $type  = @parts[1] // 'string';
    my @mods  = @parts[2 .. *].grep(*.defined);

    my Bool $reference = so @REFERENCE-TYPES.first({ $_ eq $type });
    my Bool $uniq      = so @mods.first({ $_ eq 'uniq' || $_ eq 'unique' });
    my Bool $index     = so @mods.first({ $_ eq 'index' });

    %( :$name, :$type, :$reference, :$uniq, :$index );
  }

  method parse-fields(@tokens) {
    @tokens.grep({ $_ ~~ Associative || .chars }).map({
      $_ ~~ Associative ?? $_ !! self.parse-field($_)
    }).Array;
  }

  method !col-spec(%field --> Str) {
    return '{ :reference }' if %field<reference>;
    my $spec = '{ :' ~ %field<type>;
    $spec ~= ', unique => True' if %field<uniq>;
    $spec ~ ' }';
  }

  method !column-block(@fields, Str:D $indent --> Str) {
    return '' unless @fields.elems;
    my $width = @fields.map(*.<name>.chars).max;
    @fields.map(-> %field {
      my $name = %field<name>;
      my $pad  = ' ' x ($width - $name.chars);
      $indent ~ $name ~ $pad ~ ' => ' ~ self!col-spec(%field) ~ ','
    }).join("\n");
  }

  method !index-lines(Str:D $table, @fields, Str:D $indent --> Str) {
    my @lines;
    for @fields -> %field {
      next if %field<reference> || %field<uniq>;
      next unless %field<index>;
      @lines.push: $indent ~ "self.add-index: '$table', :" ~ %field<name> ~ ';';
    }
    @lines.join("\n");
  }

  method render-create-migration(Str:D $class, Str:D $table, @tokens --> Str) {
    my @fields  = self.parse-fields(@tokens);
    my $columns = self!column-block(@fields, '      ');
    my $indexes = self!index-lines($table, @fields, '    ');

    my $up = "    self.create-table: '$table', [\n";
    $up ~= "$columns\n" if $columns;
    $up ~= "    ];";
    $up ~= "\n$indexes" if $indexes;

    qq:to/RAKU/;

    use ORM::ActiveRecord::Schema::Migration;

    class $class is Migration \{
      method up \{
    $up
      \}

      method down \{
        self.drop-table: '$table';
      \}
    \}
    RAKU
  }

  method render-add-migration(Str:D $class, Str:D $table, @tokens --> Str) {
    my @fields = self.parse-fields(@tokens);
    my @up   = @fields.map({ "    self.add-column: '$table', :" ~ .<name> ~ ' => ' ~ self!col-spec($_) ~ ';' });
    my @down = @fields.reverse.map({ "    self.remove-column: '$table', :" ~ .<name> ~ ';' });

    @up.push:   "    # add columns to '$table'" unless @up.elems;
    @down.push: "    # revert the changes to '$table'" unless @down.elems;

    qq:to/RAKU/;

    use ORM::ActiveRecord::Schema::Migration;

    class $class is Migration \{
      method up \{
    { @up.join("\n") }
      \}

      method down \{
    { @down.join("\n") }
      \}
    \}
    RAKU
  }

  method render-remove-migration(Str:D $class, Str:D $table, @tokens --> Str) {
    my @fields = self.parse-fields(@tokens);
    my @up   = @fields.map({ "    self.remove-column: '$table', :" ~ .<name> ~ ';' });
    my @down = @fields.reverse.map({ "    self.add-column: '$table', :" ~ .<name> ~ ' => ' ~ self!col-spec($_) ~ ';' });

    @up.push:   "    # remove columns from '$table'" unless @up.elems;
    @down.push: "    # restore the columns on '$table'" unless @down.elems;

    qq:to/RAKU/;

    use ORM::ActiveRecord::Schema::Migration;

    class $class is Migration \{
      method up \{
    { @up.join("\n") }
      \}

      method down \{
    { @down.join("\n") }
      \}
    \}
    RAKU
  }

  method render-empty-migration(Str:D $class --> Str) {
    qq:to/RAKU/;

    use ORM::ActiveRecord::Schema::Migration;

    class $class is Migration \{
      method up \{
      \}

      method down \{
      \}
    \}
    RAKU
  }

  # Dispatch a migration name to the right template. CreateThings, AddXToThings
  # and RemoveXFromThings get filled bodies; anything else gets an empty stub.
  method render-migration(Str:D $name, @fields --> Str) {
    my $class = self.classize($name);

    given $class {
      when /^ 'Create' $<rest>=(.+) $/ {
        self.render-create-migration($class, $<rest>.Str.lc, @fields);
      }
      when /^ 'Add' .+ 'To' $<table>=(.+) $/ {
        self.render-add-migration($class, $<table>.Str.lc, @fields);
      }
      when /^ 'Remove' .+ 'From' $<table>=(.+) $/ {
        self.render-remove-migration($class, $<table>.Str.lc, @fields);
      }
      default {
        self.render-empty-migration($class);
      }
    }
  }

  method render-model(Str:D $name, @tokens --> Str) {
    my @fields = self.parse-fields(@tokens);
    my $class = self.classize($name);
    my @references = @fields.grep(*.<reference>);

    my $body = @references.elems
      ?? @references.map({
           my $assoc = .<name>;
           "    self.belongs-to: $assoc => class-name => '" ~ self.classize($assoc) ~ "';"
         }).join("\n")
      !! '';

    my $build = $body
      ?? "  submethod BUILD \{\n$body\n  \}"
      !! "  submethod BUILD \{\n  \}";

    qq:to/RAKU/;

    use ORM::ActiveRecord::Model;

    class $class is Model \{
    $build
    \}

    GLOBAL::<$class> := $class;
    RAKU
  }

  method render-validator(Str:D $name --> Str) {
    my $class = self.classize($name);
    $class ~= 'Validator' unless $class.ends-with('Validator');

    qq:to/RAKU/;

    use ORM::ActiveRecord::Errors::Error;
    use ORM::ActiveRecord::Schema::Field;

    class $class is export \{
      method validate(\$record) \{
        # if \$record.attrs<some_column> ... \{
        #   my \$field = Field.new(:name('base'), :type('association'));
        #   \$record.errors.push(Error.new(:\$field, :message('is invalid')));
        # \}
      \}
    \}

    GLOBAL::<$class> := $class;
    RAKU
  }

  method !scope-where(@fields --> Str) {
    return '' unless @fields.elems;
    @fields.map(-> %field {
      my $token = %field<type>;
      my $value = $token eq 'string'
        ?? "True"
        !! self!scope-value($token);
      %field<name> ~ ' => ' ~ $value;
    }).join(', ');
  }

  method !scope-value(Str:D $raw --> Str) {
    return $raw if $raw ~~ /^ '-'? \d+ $/;
    return $raw if $raw eq 'True' | 'False';
    "'$raw'";
  }

  method render-scope-line(Str:D $name, @tokens --> Str) {
    my @fields = self.parse-fields(@tokens);
    my $where = self!scope-where(@fields);
    "    self.scope: '$name', -> \{ self.where(\{ $where \}) \};";
  }

  method !timestamp(--> Str) {
    return $!stamp if $!stamp.defined;
    my $now = DateTime.now(:timezone(0));
    sprintf '%04d%02d%02d%02d%02d%02d',
      $now.year, $now.month, $now.day, $now.hour, $now.minute, $now.second.Int;
  }

  method !migration-path(Str:D $kebab --> Str) {
    self.path-for($!migrate-dir, self!timestamp() ~ "-$kebab.raku");
  }

  method path-for(Str:D $dir, Str:D $file --> Str) {
    $!root.IO.add($dir).add($file).Str;
  }

  method !ensure-dir(Str:D $dir) {
    my $io = $!root.IO.add($dir);
    $io.mkdir unless $io.d;
  }

  method !write(Str:D $dir, Str:D $file, Str:D $content --> Str) {
    self!ensure-dir($dir);
    my $path = self.path-for($dir, $file);
    $path.IO.spurt($content);
    $path;
  }

  method generate-migration(Str:D $name, @tokens --> List) {
    my @fields  = self.parse-fields(@tokens);
    my $content = self.render-migration($name, @fields);
    my $file    = self!timestamp() ~ '-' ~ self.kebabize($name) ~ '.raku';
    (self!write($!migrate-dir, $file, $content),);
  }

  method generate-model(Str:D $name, @tokens --> List) {
    my @fields = self.parse-fields(@tokens);
    my $class  = self.classize($name);
    my $table  = self.tableize($name);

    my $model-path = self!write($!models-dir, "$class.rakumod", self.render-model($name, @fields));

    my $migration-class   = 'Create' ~ self.classize($table);
    my $migration-content = self.render-create-migration($migration-class, $table, @fields);
    my $migration-file    = self!timestamp() ~ '-create-' ~ $table ~ '.raku';
    my $migration-path    = self!write($!migrate-dir, $migration-file, $migration-content);

    ($model-path, $migration-path);
  }

  method generate-validator(Str:D $name --> List) {
    my $class = self.classize($name);
    $class ~= 'Validator' unless $class.ends-with('Validator');
    (self!write($!validators-dir, "$class.rakumod", self.render-validator($name)),);
  }

  method generate-scope(Str:D $model, Str:D $name, @tokens --> List) {
    my $class = self.classize($model);
    my $path  = self.path-for($!models-dir, "$class.rakumod");

    die "model file not found: $path" unless $path.IO.e;

    my @fields = self.parse-fields(@tokens);
    my $line   = self.render-scope-line($name, @fields);

    my $source = $path.IO.slurp;
    die "no 'submethod BUILD \{' block in $path; add the scope by hand"
      unless $source.contains('submethod BUILD {');

    my $updated = $source.subst("submethod BUILD \{\n", "submethod BUILD \{\n$line\n");
    $path.IO.spurt($updated);

    ($path,);
  }

  method destroy-migration(Str:D $name --> List) {
    my $kebab = self.kebabize($name);
    self!remove-migrations-matching($kebab);
  }

  method destroy-model(Str:D $name --> List) {
    my $class = self.classize($name);
    my $table = self.tableize($name);
    my @removed;

    my $model-path = self.path-for($!models-dir, "$class.rakumod");
    if $model-path.IO.e { $model-path.IO.unlink; @removed.push: $model-path }

    @removed.append: self!remove-migrations-matching('create-' ~ $table);
    @removed;
  }

  method destroy-validator(Str:D $name --> List) {
    my $class = self.classize($name);
    $class ~= 'Validator' unless $class.ends-with('Validator');

    my $path = self.path-for($!validators-dir, "$class.rakumod");
    return () unless $path.IO.e;
    $path.IO.unlink;
    ($path,);
  }

  method destroy-scope(Str:D $model, Str:D $name --> List) {
    my $class = self.classize($model);
    my $path  = self.path-for($!models-dir, "$class.rakumod");
    return () unless $path.IO.e;

    my @kept = $path.IO.lines.grep({ !(.contains("self.scope: '$name',")) });
    $path.IO.spurt(@kept.join("\n") ~ "\n");
    ($path,);
  }

  method !remove-migrations-matching(Str:D $kebab --> List) {
    my $dir = $!root.IO.add($!migrate-dir);
    return () unless $dir.d;

    my @removed;
    for dir($dir) -> $path {
      next unless $path.basename ~~ /^ \d+ '-' $kebab '.raku' $/;
      $path.unlink;
      @removed.push: $path.Str;
    }
    @removed;
  }
}
