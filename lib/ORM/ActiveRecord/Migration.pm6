
use ORM::ActiveRecord::DB;

class Migration is export {
  has DB $!db;
  has @.foreign-keys;

  submethod DESTROY {
    $!db = Nil;
  }

  submethod BUILD {
    $!db = DB.new;
  }

  method create-table(Str $table, @params) {
    self.do-create-table($table, @params);
    self.do-add-primary-key($table);
    self.do-add-foreign-keys($table);
  }

  method do-add-foreign-keys(Str $table) {
    for @!foreign-keys {
      my $sql = qq:to/SQL/;
        ALTER TABLE ONLY $table
        ADD CONSTRAINT fk_{$_}_id
        FOREIGN KEY ({$_}_id)
        REFERENCES {$_ ~ 's'}(id)
        SQL

      $!db.exec($sql);
    }

    @!foreign-keys = [];
  }

  method do-add-primary-key(Str $table) {
    my $sql = qq:to/SQL/;
      ALTER TABLE ONLY $table
      ADD CONSTRAINT {$table}_pkey PRIMARY KEY (id);
      SQL

    $!db.exec($sql);
  }

  method do-create-table(Str $table, @params) {
    my $fields = self.build-fields(@params);

    my $sql = qq:to/SQL/;
      CREATE TABLE $table ( id SERIAL, $fields )
      SQL

    $!db.exec($sql);
  }

  method build-fields(@params) {
    my @fields;

    for @params {
      my $name = $_.keys.first;
      my $type = '';
      my $limit = '';
      my $default = '';

      for $_{$name}.keys -> $attr {
        my $value = $_{$name}{$attr};

        given $attr {
          when 'string' { $type = 'VARCHAR' }
          when 'boolean' { $type = 'BOOL' }
          when 'limit' { $limit = '(' ~ $value ~ ')' }
          when 'default' { $default = $value }
          when 'reference' {
            @!foreign-keys.push($name);
            $type = 'INTEGER';
            $name = $name ~ '_id';
          }
          default { say 'unknown attr: ' ~ $attr ~ ' ' ~ $value; die }
        }
      }

      if $type ~~ 'BOOL' {
        given $default {
          when 'True' { $default = " DEFAULT 't'" }
          when 'False' { $default = " DEFAULT 'f'" }
          default { $default = '' }
        }
      }

      @fields.push($name ~ ' ' ~ $type ~ $limit ~ $default);
    }

    @fields.join(', ').trim;
  }

  method drop-table(Str $table) {
    my $sql = qq:to/SQL/;
      DROP TABLE $table
      SQL

    $!db.exec($sql);
  }
}
