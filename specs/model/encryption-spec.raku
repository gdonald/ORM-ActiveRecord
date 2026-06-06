use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Support::Secrets;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS _vaults');
  $adapter.ddl-create-table('_vaults', [
    ssn   => { :text },
    notes => { :text },
    email => { :text },
    name  => { :string, limit => 40 },
  ]);
}

class Vault is Model {
  method table-name { '_vaults' }

  submethod BUILD {
    self.encrypts('ssn', :deterministic);
    self.encrypts('notes');
    self.encrypts('email', :deterministic, :downcase);
  }
}

GLOBAL::<Vault> := Vault;

END { try $adapter.exec('DROP TABLE IF EXISTS _vaults') if $has-db }

sub raw(Str:D $col, Int:D $id) {
  my $v = $adapter.exec("SELECT $col FROM _vaults WHERE id = $id")[0][0];
  $v ~~ Blob ?? $v.decode !! $v;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'column encryption', :order<defined>, {
  before-each { encryption-keys('key-one'); Vault.destroy-all }
  after-each  { encryption-keys('key-one'); Vault.destroy-all }

  context 'deterministic encryption', :order<defined>, {
    it 'encrypts the column at rest', {
      my $v = Vault.create({ ssn => '123-45-6789' });
      expect(raw('ssn', $v.id)).not.to.eq('123-45-6789');
    }

    it 'decrypts on read', {
      my $v = Vault.create({ ssn => '123-45-6789' });
      expect(Vault.find($v.id).ssn).to.eq('123-45-6789');
    }

    it 'yields equal ciphertext for equal plaintext', {
      my $a = Vault.create({ ssn => '123-45-6789', name => 'a' });
      my $b = Vault.create({ ssn => '123-45-6789', name => 'b' });
      expect(raw('ssn', $a.id)).to.eq(raw('ssn', $b.id));
    }

    it 'is queryable by plaintext', {
      Vault.create({ ssn => '123-45-6789', name => 'a' });
      Vault.create({ ssn => '123-45-6789', name => 'b' });
      expect(Vault.where({ ssn => '123-45-6789' }).all.elems).to.eq(2);
    }
  }

  context 'random encryption', :order<defined>, {
    it 'yields different ciphertext for equal plaintext', {
      my $a = Vault.create({ notes => 'same note', name => 'a' });
      my $b = Vault.create({ notes => 'same note', name => 'b' });
      expect(raw('notes', $a.id)).not.to.eq(raw('notes', $b.id));
    }

    it 'decrypts on read', {
      my $a = Vault.create({ notes => 'same note', name => 'a' });
      expect(Vault.find($a.id).notes).to.eq('same note');
    }
  }

  context 'downcase normalisation', :order<defined>, {
    it 'normalises before encrypting', {
      my $v = Vault.create({ email => 'Foo@Bar.COM' });
      expect(Vault.find($v.id).email).to.eq('foo@bar.com');
    }

    it 'is queryable case-insensitively', {
      Vault.create({ email => 'Foo@Bar.COM', name => 'a' });
      expect(Vault.where({ email => 'FOO@BAR.COM' }).all.elems).to.eq(1);
    }
  }

  context 'key rotation', :order<defined>, {
    it 'keeps decrypting old data after a new primary key is added', {
      my $v = Vault.create({ ssn => '999-99-9999' });
      encryption-keys('key-two', 'key-one');
      expect(Vault.find($v.id).ssn).to.eq('999-99-9999');
    }
  }

  context 'backfilling existing plaintext', :order<defined>, {
    it 'encrypts a plaintext value', {
      $adapter.exec("INSERT INTO _vaults (ssn, name) VALUES ('plain-ssn', 'legacy')");
      Vault.encrypt-existing;
      my $row = Vault.where({ name => 'legacy' }).first;
      expect(raw('ssn', $row.id)).not.to.eq('plain-ssn');
    }

    it 'leaves the value decryptable', {
      $adapter.exec("INSERT INTO _vaults (ssn, name) VALUES ('plain-ssn', 'legacy')");
      Vault.encrypt-existing;
      expect(Vault.where({ name => 'legacy' }).first.ssn).to.eq('plain-ssn');
    }
  }
}
