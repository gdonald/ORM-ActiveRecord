use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Support::TestSkip;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter     = DB.shared.adapter;
my $has-db      = $adapter.defined && $adapter.is-connected;
my $current     = $has-db ?? configured-adapter-name(:check-config) !! Str;
my $is-pg       = $current.defined && $current eq 'pg';
my $skip-reason = !$has-db
  ?? 'no database connection available'
  !! (!$is-pg ?? 'extensions and enums are PostgreSQL-only' !! Str);

sub enum-exists(Str:D $name --> Bool) {
  return False unless $is-pg;
  ?$adapter.exec("SELECT 1 FROM pg_type WHERE typname = '$name' AND typtype = 'e'").elems;
}

sub enum-values(Str:D $name --> List) {
  return () unless $is-pg;
  $adapter.exec(qq:to/SQL/).map({ $_[0] }).list;
    SELECT e.enumlabel
      FROM pg_enum e
      JOIN pg_type t ON t.oid = e.enumtypid
     WHERE t.typname = '$name'
     ORDER BY e.enumsortorder
    SQL
}

sub extension-exists(Str:D $name --> Bool) {
  return False unless $is-pg;
  ?$adapter.exec("SELECT 1 FROM pg_extension WHERE extname = '$name'").elems;
}

# Pick an extension that the server actually ships, so the test does not assume
# a specific contrib package is installed. Skips the extension examples if none
# of the usual candidates are available.
sub available-extension(--> Str) {
  return Str unless $is-pg;
  my @candidates = <pgcrypto citext hstore unaccent>;
  my $list = @candidates.map({ "'$_'" }).join(', ');
  my @rows = $adapter.exec("SELECT name FROM pg_available_extensions WHERE name IN ($list)").map({ $_[0] }).list;
  @candidates.first({ $_ (elem) @rows.Set }) // Str;
}

my $ext = available-extension();

sub drop-enums {
  for <_mood _status> -> $e {
    try { $adapter.exec("DROP TYPE IF EXISTS $e") if $is-pg }
  }
}

class CreateMood is Migration {
  method change {
    self.create-enum: '_mood', <sad neutral happy>;
  }
}

class AddEcstatic is Migration {
  method up {
    self.add-enum-value: '_mood', 'ecstatic', after => 'happy';
  }
  method down {
    self.irreversible-migration;
  }
}

class RenameNeutral is Migration {
  method change {
    self.rename-enum-value: '_mood', 'neutral', 'meh';
  }
}

class EnableExt is Migration {
  has Str $.ext is rw;
  method change {
    self.enable-extension: $!ext;
  }
}

my &group = ($has-db && $is-pg) ?? &describe !! &xdescribe;

group 'migration extensions and enums', :order<defined>, {
  if !($has-db && $is-pg) { pending $skip-reason // 'not applicable'; }

  before-all { drop-enums() if $is-pg }
  after-all  { drop-enums() if $is-pg }

  context 'create-enum', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $is-pg { CreateMood.new.up } }

      it 'creates the enum type', {
        expect(enum-exists('_mood')).to.be-truthy;
      }

      it 'creates the values in declared order', {
        expect(enum-values('_mood')).to.eq(<sad neutral happy>.list);
      }
    }

    context 'after down (auto-inverts to drop-enum)', :order<defined>, {
      before-all { if $is-pg { CreateMood.new.down } }

      it 'drops the enum type', {
        expect(enum-exists('_mood')).to.be-falsy;
      }
    }
  }

  context 'add-enum-value with :after', :order<defined>, {
    before-all {
      if $is-pg {
        CreateMood.new.up;
        AddEcstatic.new.up;
      }
    }
    after-all { drop-enums() if $is-pg }

    it 'appends the value at the requested position', {
      expect(enum-values('_mood')).to.eq(<sad neutral happy ecstatic>.list);
    }

    it 'is irreversible inside change', {
      expect({ AddEcstatic.new.down }).to.raise-error(X::IrreversibleMigration);
    }
  }

  context 'rename-enum-value', :order<defined>, {
    before-all { if $is-pg { CreateMood.new.up } }
    after-all  { drop-enums() if $is-pg }

    context 'after up', :order<defined>, {
      before-all { if $is-pg { RenameNeutral.new.up } }

      it 'renames the value', {
        expect(enum-values('_mood')).to.eq(<sad meh happy>.list);
      }
    }

    context 'after down (swaps from/to)', :order<defined>, {
      before-all { if $is-pg { RenameNeutral.new.down } }

      it 'restores the original value name', {
        expect(enum-values('_mood')).to.eq(<sad neutral happy>.list);
      }
    }
  }

  my &ext-group = ($is-pg && $ext.defined) ?? &context !! &xcontext;

  ext-group 'enable-extension / disable-extension', :order<defined>, {
    if !($is-pg && $ext.defined) { pending 'no candidate extension available on this server'; }

    my Bool $after-up   = False;
    my Bool $after-down = True;

    before-all {
      if $is-pg && $ext.defined {
        my $m = EnableExt.new(:$ext);
        $m.up;
        $after-up = extension-exists($ext);
        $m.down;
        $after-down = extension-exists($ext);
      }
    }

    it 'enables the extension on up', {
      expect($after-up).to.be-truthy;
    }

    it 'disables the extension on down', {
      expect($after-down).to.be-falsy;
    }
  }
}
