use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Relation::Scopes;

%*ENV<DISABLE-SQL-LOG> = True;

class ScImage is Model {
  method table-name { 'images' }

  $?CLASS.scope: 'jpgs', -> { $?CLASS.where({ext => 'jpg'}) }

  submethod BUILD {
    self.validate: 'name', { :presence }
    self.validate: 'ext', { :presence, inclusion => { in => <gif jpeg jpg png> } }
  }
}

describe 'Model.scope', {
  my ($foo, $bar, $baz);

  before-each {
    ScImage.destroy-all;
    $foo = ScImage.create({name => 'foo', ext => 'jpg'});
    $bar = ScImage.create({name => 'bar', ext => 'jpg'});
    $baz = ScImage.create({name => 'baz', ext => 'png'});
  }

  after-each {
    ScImage.destroy-all;
  }

  it 'sees every row in the table', {
    expect(ScImage.count).to.eq(3);
  }

  it 'includes the first jpg', {
    my @images = ScImage.jpgs.all;

    expect(@images.grep(* == $foo).elems).to.be-greater-than(0);
  }

  it 'includes the second jpg', {
    my @images = ScImage.jpgs.all;

    expect(@images.grep(* == $bar).elems).to.be-greater-than(0);
  }

  it 'excludes the png', {
    my @images = ScImage.jpgs.all;

    expect(@images.grep(* == $baz).elems).to.eq(0);
  }

  # A model's `submethod BUILD` runs on every instantiation, so a `scope`
  # declared there is re-declared for every record built. The registry keeps one
  # entry per (owning class, scope name) rather than one per record.
  context 'the scope registry', {
    it 'holds one entry however many records are built', {
      ScImage.create({name => 'one', ext => 'jpg'});
      ScImage.create({name => 'two', ext => 'jpg'});
      my $before = Scopes.scopes.grep({ .name eq 'jpgs' }).elems;

      ScImage.create({name => 'three', ext => 'jpg'});

      expect(Scopes.scopes.grep({ .name eq 'jpgs' }).elems).to.eq($before);
    }

    it 'still finds the scope for its own class', {
      expect(Scopes.exists('jpgs', ScImage)).to.be-truthy;
    }

    it 'does not find it for an unrelated class', {
      expect(Scopes.exists('jpgs', Model)).to.be-falsy;
    }

    it 'does not find a name nothing declared', {
      expect(Scopes.exists('nonesuch', ScImage)).to.be-falsy;
    }
  }
}
