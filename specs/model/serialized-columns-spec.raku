use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Type;
use ORM::ActiveRecord::Type::Yaml;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS _accounts');
  $adapter.ddl-create-table('_accounts', [
    prefs    => { :text },
    settings => { :text },
    tags     => { :text },
    name     => { :string, limit => 40 },
  ]);
}

class PipeCoder {
  method dump($v)  { $v ~~ Positional ?? $v.join('|') !! $v }
  method load($s)  { $s.defined && $s.Str.chars ?? $s.Str.split('|').list !! () }
}

class Account is Model {
  method table-name { '_accounts' }

  submethod BUILD {
    self.store('prefs', accessors => ['theme', 'locale']);
    self.serialize('settings', YamlCoder.new);
    self.store-accessor('settings', 'sound');
    self.serialize('tags', PipeCoder.new);
  }
}

GLOBAL::<Account> := Account;

END { try $adapter.exec('DROP TABLE IF EXISTS _accounts') if $has-db }

sub raw(Str:D $col, Int:D $id) {
  my $v = $adapter.exec("SELECT $col FROM _accounts WHERE id = $id")[0][0];
  $v ~~ Blob ?? $v.decode !! $v;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'serialized columns', :order<defined>, {
  before-each { Account.destroy-all }
  after-each  { Account.destroy-all }

  context 'store with the default JSON coder', :order<defined>, {
    it 'reads a key through a store accessor', {
      my $a = Account.create({ prefs => { theme => 'dark', locale => 'en' } });
      expect(Account.find($a.id).theme).to.eq('dark');
    }

    it 'serializes the column as JSON', {
      my $a = Account.create({ prefs => { theme => 'dark' } });
      expect(raw('prefs', $a.id)).to.match(/'"theme"'/);
    }

    it 'persists a key written through a store accessor', {
      my $a = Account.create({ prefs => { theme => 'dark' } });
      $a.theme = 'light';
      $a.save;
      expect(Account.find($a.id).theme).to.eq('light');
    }
  }

  context 'YAML serialization', :order<defined>, {
    it 'round-trips a YAML-serialized column', {
      my $a = Account.create({ settings => { sound => 'loud', volume => 5 } });
      expect(Account.find($a.id).settings<sound>).to.eq('loud');
    }

    it 'serializes the column as YAML', {
      my $a = Account.create({ settings => { sound => 'loud' } });
      expect(raw('settings', $a.id)).to.match(/'sound'/);
    }
  }

  context 'after-the-fact store accessor', :order<defined>, {
    it 'reads a key', {
      my $a = Account.create({ settings => { sound => 'loud' } });
      expect($a.sound).to.eq('loud');
    }

    it 'persists a written key', {
      my $a = Account.create({ settings => { sound => 'loud' } });
      $a.sound = 'quiet';
      $a.save;
      expect(Account.find($a.id).sound).to.eq('quiet');
    }
  }

  context 'custom coder', :order<defined>, {
    it 'serializes to the column', {
      my $a = Account.create({ tags => ['x', 'y', 'z'] });
      expect(raw('tags', $a.id)).to.eq('x|y|z');
    }

    it 'deserializes from the column', {
      my $a = Account.create({ tags => ['x', 'y', 'z'] });
      expect(Account.find($a.id).tags.sort.list).to.eq(('x', 'y', 'z'));
    }
  }
}
