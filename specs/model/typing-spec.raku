use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Type;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

# A custom attribute type: a Raku list <-> comma-separated text column.
class CsvType does AttributeType {
  method cast($v) {
    return $v.list if $v ~~ Positional;
    return [] unless $v.defined && $v.Str.chars;
    $v.Str.split(',').list;
  }
  method deserialize($v) {
    return [] unless $v.defined && $v.Str.chars;
    $v.Str.split(',').list;
  }
  method serialize($v) {
    $v ~~ Positional ?? $v.join(',') !! $v;
  }
}

if $has-db {
  try { $adapter.ddl-drop-table('_ty_widgets') if table-exists('_ty_widgets') }
  $adapter.ddl-create-table('_ty_widgets', [
    raw   => { :text },
    prefs => { :text },
    level => { :integer },
    token => { :string, limit => 32 },
  ]);
}

class TyWidget is Model {
  method table-name { '_ty_widgets' }

  submethod BUILD {
    self.attribute('raw', CsvType.new);
    self.serialize('prefs', JsonCoder.new);
    self.attribute('level', :default(5));
    self.attribute('token', :default(-> { 'gen-token' }));
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'model type system', :order<defined>, {
  before-all { TyWidget.destroy-all if $has-db }
  after-all  {
    if $has-db {
      TyWidget.destroy-all;
      try { $adapter.ddl-drop-table('_ty_widgets') }
    }
  }

  context 'type registry', {
    it 'pre-registers the built-in integer type', {
      expect(Type.is-registered('integer')).to.be-truthy;
    }

    it 'looks up a built-in type as the right class', {
      expect(Type.lookup('integer') ~~ IntegerType).to.be-truthy;
    }

    it 'registers and looks up a custom type', {
      Type.register('csv', CsvType.new);
      expect(Type.lookup('csv') ~~ CsvType).to.be-truthy;
    }
  }

  context 'custom attribute type', :order<defined>, {
    it 'round-trips a custom-typed attribute through the database', {
      my $w = TyWidget.create({ raw => ['x', 'y', 'z'], prefs => {}, level => 1, token => 't' });
      my $f = TyWidget.find($w.id);
      expect($f.raw.join(',')).to.eq('x,y,z');
    }
  }

  context 'serialized attribute', :order<defined>, {
    it 'round-trips a serialized hash through the database', {
      my $w = TyWidget.create({ raw => [], prefs => { theme => 'dark', size => 3 }, level => 1, token => 't' });
      my $f = TyWidget.find($w.id);
      expect($f.prefs<theme>).to.eq('dark');
    }
  }

  context 'defaults on a new record', :order<defined>, {
    it 'applies a value default', {
      expect(TyWidget.build({}).level).to.eq(5);
    }

    it 'applies a block default', {
      expect(TyWidget.build({}).token).to.eq('gen-token');
    }

    it 'does not override a supplied value with the default', {
      expect(TyWidget.build({ level => 9 }).level).to.eq(9);
    }
  }
}
