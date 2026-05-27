use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use JSON::Tiny;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS is_widgets');
  $adapter.ddl-create-table('is_widgets', [
    name     => { :string, limit => 64 },
    password => { :string, limit => 64 },
    qty      => { :integer, default => 0 },
    active   => { :boolean, default => False },
  ]);
  $adapter.ddl-add-timestamps('is_widgets');

  $adapter.exec('DROP TABLE IF EXISTS is_gadgets');
  $adapter.ddl-create-table('is_gadgets', [
    label => { :string, limit => 64 },
  ]);
}

class IsWidget is Model {
  method table-name { 'is_widgets' }

  submethod BUILD {
    self.filter-attribute('password');
  }

  method shout { (self.name // '').uc }
}

class IsGadget is Model {
  method table-name { 'is_gadgets' }
}

END {
  if $has-db {
    try $adapter.exec('DROP TABLE IF EXISTS is_widgets');
    try $adapter.exec('DROP TABLE IF EXISTS is_gadgets');
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'identity and serialization', {
  context 'to-param', {
    it 'is undefined for a new record', {
      my $w = IsWidget.new(:id(0));

      expect($w.to-param.defined).to.be-falsy;
    }

    it 'returns the id as a string for a persisted record', {
      my $saved = IsWidget.create({ name => 'a', qty => 1 });

      expect($saved.to-param).to.eq($saved.id.Str);
    }

    it 'is a Str', {
      my $saved = IsWidget.create({ name => 'a', qty => 1 });

      expect($saved.to-param).to.be-a(Str);
    }
  }

  context 'to-key', {
    it 'is undefined for a new record', {
      my $w = IsWidget.new(:id(0));

      expect($w.to-key.defined).to.be-falsy;
    }

    it 'returns [id] for a persisted record', {
      my $saved = IsWidget.create({ name => 'b', qty => 2 });

      expect($saved.to-key).to.eq([$saved.id]);
    }
  }

  context 'instance cache-key for an unsaved record', {
    it 'returns is_widgets/new', {
      my $w = IsWidget.new(:id(0));

      expect($w.cache-key).to.eq('is_widgets/new');
    }
  }

  context 'instance cache-key for a persisted record', {
    my $a;

    before-each {
      $a = IsWidget.create({ name => 'cka', qty => 1 });
    }

    it 'returns table/id', {
      expect($a.cache-key).to.eq('is_widgets/' ~ $a.id);
    }

    it 'has a defined cache-version when updated_at is present', {
      expect($a.cache-version.defined).to.be-truthy;
    }

    it 'joins cache-key and cache-version', {
      expect($a.cache-key-with-version).to.eq($a.cache-key ~ '-' ~ $a.cache-version);
    }
  }

  context 'instance cache-key without timestamps', {
    my $g;

    before-each {
      $g = IsGadget.create({ label => 'g1' });
    }

    it 'returns table/id', {
      expect($g.cache-key).to.eq('is_gadgets/' ~ $g.id);
    }

    it 'has an undefined cache-version without updated_at', {
      expect($g.cache-version.defined).to.be-falsy;
    }

    it 'falls back to cache-key without a version', {
      expect($g.cache-key-with-version).to.eq($g.cache-key);
    }
  }

  context 'class-level cache-key', {
    it 'routes to the relation cache key', {
      expect(IsWidget.cache-key).to.match(/^ 'is_widgets/query-' /);
    }
  }

  context 'serializable-hash', {
    my $w;

    before-each {
      $w = IsWidget.create({ name => 'json1', qty => 7, active => True });
    }

    it 'includes the name', {
      my %h = $w.serializable-hash;

      expect(%h<name>).to.eq('json1');
    }

    it 'includes the qty', {
      my %h = $w.serializable-hash;

      expect(%h<qty>).to.eq(7);
    }

    it 'includes the id', {
      my %h = $w.serializable-hash;

      expect(%h<id>:exists).to.be-truthy;
    }

    it 'includes filtered keys (filtering is inspect-only)', {
      my %h = $w.serializable-hash;

      expect(%h<password>:exists).to.be-truthy;
    }

    it ':only filters keys', {
      my %only = $w.serializable-hash(:only<name qty>);

      expect(%only.keys.sort.join(',')).to.eq('name,qty');
    }

    it ':except drops keys', {
      my %except = $w.serializable-hash(:except<password created_at updated_at>);

      expect(%except<password>:exists).to.be-falsy;
    }

    it ':except keeps other keys', {
      my %except = $w.serializable-hash(:except<password created_at updated_at>);

      expect(%except<name>:exists).to.be-truthy;
    }

    it ':methods adds method results', {
      my %methods = $w.serializable-hash(:only<name>, :methods<shout>);

      expect(%methods<shout>).to.eq('JSON1');
    }
  }

  context 'as-json', {
    it 'coerces DateTime to Str', {
      my $w = IsWidget.create({ name => 'json1', qty => 7, active => True });
      my %json-h = $w.as-json;

      expect(%json-h<updated_at>).to.be-a(Str);
    }
  }

  context 'to-json round-trip', {
    my $parsed;

    before-each {
      my $w = IsWidget.create({ name => 'json1', qty => 7, active => True });
      $parsed = from-json($w.to-json(:only<name qty active>));
    }

    it 'round-trips the name', {
      expect($parsed<name>).to.eq('json1');
    }

    it 'round-trips the qty', {
      expect($parsed<qty>).to.eq(7);
    }

    it 'round-trips active', {
      expect($parsed<active>).to.eq(True);
    }
  }

  context 'attribute-for-inspect', {
    my $w;

    before-each {
      $w = IsWidget.create({ name => 'inspect-me', qty => 3, active => True });
    }

    it 'quotes strings', {
      expect($w.attribute-for-inspect('name')).to.eq('"inspect-me"');
    }

    it 'renders integers bare', {
      expect($w.attribute-for-inspect('qty')).to.eq('3');
    }

    it 'renders booleans', {
      expect($w.attribute-for-inspect('active')).to.eq('True');
    }

    it 'truncates long strings to 50 + quotes + ellipsis', {
      my $long = 'x' x 80;
      my $w2 = IsWidget.new(:id(0));
      $w2.write-attribute('name', $long);

      expect($w2.attribute-for-inspect('name').chars).to.eq(55);
    }

    it 'ends with ..." after truncation', {
      my $long = 'x' x 80;
      my $w2 = IsWidget.new(:id(0));
      $w2.write-attribute('name', $long);

      expect($w2.attribute-for-inspect('name').ends-with('..."')).to.be-truthy;
    }
  }

  context 'inspect', {
    my $s;

    before-each {
      my $w = IsWidget.create({ name => 'inspect-me', qty => 3, active => True });
      $s = $w.inspect;
    }

    it 'starts with #<Class', {
      expect($s).to.match(/^ '#<' .*? 'IsWidget '/);
    }

    it 'ends with >', {
      expect($s.ends-with('>')).to.be-truthy;
    }

    it 'renders the name', {
      expect($s.contains('name: "inspect-me"')).to.be-truthy;
    }

    it 'renders the qty', {
      expect($s.contains('qty: 3')).to.be-truthy;
    }
  }

  context 'filter-attributes', {
    my $w;

    before-each {
      $w = IsWidget.create({ name => 'secret-owner', password => 'hunter2', qty => 1 });
    }

    it 'shows [FILTERED] in attribute-for-inspect', {
      expect($w.attribute-for-inspect('password')).to.eq('[FILTERED]');
    }

    it 'redacts filtered attributes in inspect', {
      expect($w.inspect.contains('password: [FILTERED]')).to.be-truthy;
    }

    it 'does NOT redact in serializable-hash (Rails parity)', {
      expect($w.serializable-hash<password>).to.eq('hunter2');
    }
  }

  context 'gist', {
    it 'routes to inspect for defined instances', {
      my $w = IsWidget.create({ name => 'gistly', qty => 1 });

      expect($w.gist).to.match(/^ '#<' .*? 'IsWidget '/);
    }
  }
}
