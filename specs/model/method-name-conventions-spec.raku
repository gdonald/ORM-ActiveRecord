use lib 'lib';
use BDD::Behave;

class D {
  method save-or-die { 'ok' }
  method is-valid    { True  }
}

describe 'Raku-idiomatic method-name conventions', {
  it 'allows the -or-die suffix on method identifiers', {
    expect(D.new.save-or-die).to.eq('ok');
  }

  it 'allows the is- prefix on predicate method identifiers', {
    expect(D.new.is-valid).to.be-truthy;
  }
}
