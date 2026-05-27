use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

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
}
