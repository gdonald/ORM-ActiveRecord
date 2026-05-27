use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS aa_widgets');
  $adapter.ddl-create-table('aa_widgets', [
    name   => { :string, limit => 64 },
    qty    => { :integer, default => 0 },
    active => { :boolean, default => False },
  ]);
}

class AaWidget is Model {
  method table-name { 'aa_widgets' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS aa_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'attribute access', {
  context 'assign-attributes', {
    my $w;

    before-each {
      $w = AaWidget.build;
      $w.assign-attributes({ name => 'Alpha', qty => 7 });
    }

    it 'sets a string column', {
      expect($w.name).to.eq('Alpha');
    }

    it 'sets an integer column', {
      expect($w.qty).to.eq(7);
    }

    it 'does not save the record', {
      expect($w.id).to.eq(0);
    }

    it 'is chainable (returns self)', {
      my $w2  = AaWidget.build;
      my $ret = $w2.assign-attributes({ name => 'Beta' });

      expect($ret === $w2).to.be-truthy;
    }
  }

  context 'attributes= setter', {
    my $w;

    before-each {
      $w = AaWidget.build;
      $w.attributes = { name => 'Gamma', qty => 3 };
    }

    it 'assigns the name', {
      expect($w.name).to.eq('Gamma');
    }

    it 'assigns the qty', {
      expect($w.qty).to.eq(3);
    }
  }

  context 'read-attribute / write-attribute', {
    my $w;

    before-each {
      $w = AaWidget.build({ name => 'Delta' });
    }

    it 'read-attribute returns the current value', {
      expect($w.read-attribute('name')).to.eq('Delta');
    }

    it 'write-attribute mutates the value', {
      $w.write-attribute('name', 'Echo');

      expect($w.name).to.eq('Echo');
    }

    it 'read-attribute reflects writes', {
      $w.write-attribute('name', 'Echo');

      expect($w.read-attribute('name')).to.eq('Echo');
    }
  }

  context '[] / []= indexer access', {
    my $w;

    before-each {
      $w = AaWidget.build({ name => 'Foxtrot', qty => 2 });
    }

    it 'reads a string attribute', {
      expect($w<name>).to.eq('Foxtrot');
    }

    it 'reads an integer attribute', {
      expect($w<qty>).to.eq(2);
    }

    it 'writes an attribute', {
      $w<name> = 'Golf';

      expect($w<name>).to.eq('Golf');
    }

    it 'method accessor sees the new value', {
      $w<name> = 'Golf';

      expect($w.name).to.eq('Golf');
    }

    it ':exists is true for a known attribute', {
      expect($w<name>:exists).to.be-truthy;
    }

    it ':exists is false for an unknown attribute', {
      expect($w<bogus>:exists).to.be-falsy;
    }
  }

  context 'is-attribute-present (Rails present? semantics)', {
    my $w;
    my $blank;

    before-each {
      $w     = AaWidget.build({ name => 'Hotel', qty => 5, active => True });
      $blank = AaWidget.build({ name => '', qty => 0, active => False });
    }

    it 'reports a non-empty string as present', {
      expect($w.is-attribute-present('name')).to.be-truthy;
    }

    it 'reports a non-zero int as present', {
      expect($w.is-attribute-present('qty')).to.be-truthy;
    }

    it 'reports a True bool as present', {
      expect($w.is-attribute-present('active')).to.be-truthy;
    }

    it 'reports an empty string as not present', {
      expect($blank.is-attribute-present('name')).to.be-falsy;
    }

    it 'reports zero as present (matches Rails)', {
      expect($blank.is-attribute-present('qty')).to.be-truthy;
    }

    it 'reports a False bool as not present', {
      expect($blank.is-attribute-present('active')).to.be-falsy;
    }

    it 'reports an unknown attribute as not present', {
      expect($blank.is-attribute-present('bogus')).to.be-falsy;
    }
  }

  context 'has-attribute', {
    my $w;

    before-each {
      $w = AaWidget.build;
    }

    it 'is true for a schema column', {
      expect($w.has-attribute('name')).to.be-truthy;
    }

    it 'is true for another schema column', {
      expect($w.has-attribute('qty')).to.be-truthy;
    }

    it 'is true for the id column', {
      expect($w.has-attribute('id')).to.be-truthy;
    }

    it 'is false for a non-column', {
      expect($w.has-attribute('bogus')).to.be-falsy;
    }
  }

  context 'attribute-names', {
    my @names;

    before-each {
      @names = AaWidget.build.attribute-names;
    }

    it 'lists at least all schema columns', {
      expect(@names.elems).to.be-greater-than-or-equal-to(4);
    }

    it 'includes name', {
      expect(@names.Set{'name'}).to.be-truthy;
    }

    it 'includes qty', {
      expect(@names.Set{'qty'}).to.be-truthy;
    }

    it 'includes id', {
      expect(@names.Set{'id'}).to.be-truthy;
    }
  }

  context 'attributes hash dump', {
    my $w;
    my %dump;

    before-each {
      $w    = AaWidget.build({ name => 'India', qty => 9 });
      %dump = $w.attributes;
    }

    it 'has the name', {
      expect(%dump<name>).to.eq('India');
    }

    it 'has the qty', {
      expect(%dump<qty>).to.eq(9);
    }

    it 'returns a clone, not a live view', {
      %dump<name> = 'Juliet';

      expect($w.name).to.eq('India');
    }
  }
}
