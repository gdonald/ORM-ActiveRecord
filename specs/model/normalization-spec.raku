use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS _contacts');
  $adapter.ddl-create-table('_contacts', [
    email => { :string, limit => 120 },
    phone => { :string, limit => 40 },
    name  => { :string, limit => 60 },
  ]);
}

class Contact is Model {
  method table-name { '_contacts' }

  submethod BUILD {
    self.normalizes('email', :with(-> $v { $v.trim.lc }));
    self.normalizes('phone', 'name', :with(-> $v { $v.trim }));
  }
}

GLOBAL::<Contact> := Contact;

END { try $adapter.exec('DROP TABLE IF EXISTS _contacts') if $has-db }

my &group = $has-db ?? &describe !! &xdescribe;

group 'attribute normalisation', :order<defined>, {
  before-each { Contact.destroy-all }
  after-each  { Contact.destroy-all }

  context 'on save', :order<defined>, {
    it 'normalises the value in memory', {
      expect(Contact.create({ email => '  Foo@Bar.COM ' }).email).to.eq('foo@bar.com');
    }

    it 'persists the normalised value', {
      my $c = Contact.create({ email => '  Foo@Bar.COM ' });
      expect(Contact.find($c.id).email).to.eq('foo@bar.com');
    }

    it 'normalises the first of several attributes', {
      expect(Contact.create({ phone => '  555-1234 ' }).phone).to.eq('555-1234');
    }

    it 'normalises the second of several attributes', {
      expect(Contact.create({ name => '  Bob  ' }).name).to.eq('Bob');
    }
  }

  context 'on query', :order<defined>, {
    it 'normalises the search value to match the stored value', {
      my $c = Contact.create({ email => '  Foo@Bar.COM ' });
      expect(Contact.where({ email => '  FOO@BAR.COM ' }).first.id).to.eq($c.id);
    }
  }

  context 'normalize-value-for', :order<defined>, {
    before-each { Contact.create({ email => 'seed@x.com' }) }

    it 'applies the normaliser to a value', {
      expect(Contact.normalize-value-for('email', '  AB@C.D ')).to.eq('ab@c.d');
    }

    it 'leaves an un-normalised attribute alone', {
      expect(Contact.normalize-value-for('missing', '  x  ')).to.eq('  x  ');
    }
  }
}
