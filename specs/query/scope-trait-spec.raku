use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class TraitScImage is Model {
  method table-name { 'images' }
  method jpgs is scope { self.where({ ext => 'jpg' }) }
  method by-ext($ext) is scope { self.where({ ext => $ext }) }
}

class ArgScImage is Model {
  method table-name { 'images' }
  $?CLASS.scope: 'with-ext', -> $ext { $?CLASS.where({ ext => $ext }) }
}

class SharedScJpg is Model {
  method table-name { 'images' }
  $?CLASS.scope: 'shared', -> { $?CLASS.where({ ext => 'jpg' }) }
}

class SharedScPng is Model {
  method table-name { 'images' }
  $?CLASS.scope: 'shared', -> { $?CLASS.where({ ext => 'png' }) }
}

describe 'the `is scope` trait', {
  before-each {
    TraitScImage.destroy-all;
    TraitScImage.create({ name => 'a', ext => 'jpg' });
    TraitScImage.create({ name => 'b', ext => 'png' });
  }

  after-each { TraitScImage.destroy-all }

  it 'runs a method marked `is scope` as a named scope', {
    expect(TraitScImage.jpgs.all.map(*.attrs<ext>).unique.sort.List).to.eq(('jpg',));
  }

  it 'passes arguments to a method scope', {
    expect(TraitScImage.by-ext('png').all.map(*.attrs<ext>).unique.sort.List).to.eq(('png',));
  }
}

describe 'a scope block that takes an argument', {
  before-each {
    ArgScImage.destroy-all;
    ArgScImage.create({ name => 'a', ext => 'jpg' });
    ArgScImage.create({ name => 'b', ext => 'png' });
  }

  after-each { ArgScImage.destroy-all }

  it 'passes the call-site argument to the scope block', {
    expect(ArgScImage.with-ext('png').all.map(*.attrs<ext>).unique.sort.List).to.eq(('png',));
  }
}

describe 'per-class scope resolution', {
  before-each {
    TraitScImage.destroy-all;
    TraitScImage.create({ name => 'a', ext => 'jpg' });
    TraitScImage.create({ name => 'b', ext => 'png' });
  }

  after-each { TraitScImage.destroy-all }

  it 'resolves a same-named scope to its own class', {
    expect(SharedScJpg.shared.all.map(*.attrs<ext>).unique.sort.List).to.eq(('jpg',));
  }

  it 'does not collide with a same-named scope on another class', {
    expect(SharedScPng.shared.all.map(*.attrs<ext>).unique.sort.List).to.eq(('png',));
  }
}
