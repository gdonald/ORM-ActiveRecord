use lib 'lib';
use BDD::Behave;

class D {
  method save-bang { 'ok' }
  method is-valid    { True  }
}

describe 'Raku-idiomatic method-name conventions', {
  it 'allows the -bang suffix on method identifiers', {
    expect(D.new.save-bang).to.eq('ok');
  }

  it 'allows the is- prefix on predicate method identifiers', {
    expect(D.new.is-valid).to.be-truthy;
  }
}
