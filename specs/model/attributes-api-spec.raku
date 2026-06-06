use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Type;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS attr_widgets');
  $adapter.ddl-create-table('attr_widgets', [
    name => { :string, limit => 40 },
    qty  => { :integer, default => 0 },
    tags => { :text },
  ]);
}

class AttrCsvType does AttributeType {
  method cast($v) {
    return $v.list if $v ~~ Positional;
    $v.defined ?? $v.Str.split(',').grep(*.chars).list !! $v;
  }
  method deserialize($v) {
    $v.defined && $v.Str.chars ?? $v.Str.split(',').grep(*.chars).list !! ();
  }
  method serialize($v) {
    $v ~~ Positional ?? $v.join(',') !! $v;
  }
}

Type.register('attr-csv', AttrCsvType.new);

class AttrWidget is Model {
  method table-name { 'attr_widgets' }

  submethod BUILD {
    self.attribute('score', 'integer', :default(10));
    self.attribute('label', :default(-> { 'tag' }));
    self.attribute('tags', 'attr-csv');
  }
}

GLOBAL::<AttrWidget> := AttrWidget;

END { try $adapter.exec('DROP TABLE IF EXISTS attr_widgets') if $has-db }

my &group = $has-db ?? &describe !! &xdescribe;

group 'attributes API', :order<defined>, {
  before-each { AttrWidget.destroy-all }
  after-each  { AttrWidget.destroy-all }

  context 'virtual attributes', :order<defined>, {
    it 'applies a value default', {
      expect(AttrWidget.create({ name => 'a' }).score).to.eq(10);
    }

    it 'applies a block default', {
      expect(AttrWidget.create({ name => 'a' }).label).to.eq('tag');
    }

    it 'casts a supplied value with the declared type', {
      expect(AttrWidget.create({ name => 'b', score => '42' }).score).to.eq(42);
    }

    it 'is writable', {
      my $w = AttrWidget.create({ name => 'b' });
      $w.score = 7;
      expect($w.score).to.eq(7);
    }

    it 'is recognised by has-attribute', {
      expect(AttrWidget.create({ name => 'a' }).has-attribute('score')).to.be-truthy;
    }

    it 'is not persisted', {
      my $w = AttrWidget.create({ name => 'c', score => 99 });
      expect(AttrWidget.find($w.id).score).to.eq(10);
    }
  }

  context 'custom column type', :order<defined>, {
    it 'serialises to the column', {
      my $w = AttrWidget.create({ name => 'd', tags => ['x', 'y', 'z'] });
      my $raw = $adapter.exec("SELECT tags FROM attr_widgets WHERE id = {$w.id}")[0][0];
      $raw = $raw.decode if $raw ~~ Blob;
      expect($raw).to.eq('x,y,z');
    }

    it 'deserialises from the column', {
      my $w = AttrWidget.create({ name => 'd', tags => ['x', 'y', 'z'] });
      expect(AttrWidget.find($w.id).tags.sort.list).to.eq(('x', 'y', 'z'));
    }
  }
}
