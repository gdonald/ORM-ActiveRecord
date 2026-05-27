use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class Contract is Model {
  submethod BUILD { }
}

class Article is Model {
  submethod BUILD { }
}

describe 'Bool round-trip through coerce-write / coerce-read', {
  before-each {
    Contract.destroy-all;
  }

  after-each {
    Contract.destroy-all;
  }

  context 'when terms is True', {
    it 'creates the contract with an id', {
      my $c = Contract.create({ name => 'Round-trip True', terms => True });
      expect($c.id).to.be-truthy;
    }

    it 'reads terms back as Bool', {
      my $c = Contract.create({ name => 'Round-trip True', terms => True });
      my $found = Contract.find($c.id);
      expect($found.attrs<terms>).to.be-a(Bool);
    }

    it 'preserves the True value on read', {
      my $c = Contract.create({ name => 'Round-trip True', terms => True });
      my $found = Contract.find($c.id);
      expect($found.attrs<terms>).to.eq(True);
    }
  }

  context 'when terms is False', {
    it 'creates the contract with an id (False no longer mangled to "")', {
      my $c2 = Contract.create({ name => 'Round-trip False', terms => False });
      expect($c2.id).to.be-truthy;
    }

    it 'reads terms back as Bool', {
      my $c2 = Contract.create({ name => 'Round-trip False', terms => False });
      my $found2 = Contract.find($c2.id);
      expect($found2.attrs<terms>).to.be-a(Bool);
    }

    it 'preserves the False value on read', {
      my $c2 = Contract.create({ name => 'Round-trip False', terms => False });
      my $found2 = Contract.find($c2.id);
      expect($found2.attrs<terms>).to.eq(False);
    }
  }

  context 'when updating True to False', {
    it 'reads updated terms back as Bool', {
      my $c = Contract.create({ name => 'Round-trip True', terms => True });
      $c.update({ terms => False });
      my $reloaded = Contract.find($c.id);
      expect($reloaded.attrs<terms>).to.be-a(Bool);
    }

    it 'persists the False value', {
      my $c = Contract.create({ name => 'Round-trip True', terms => True });
      $c.update({ terms => False });
      my $reloaded = Contract.find($c.id);
      expect($reloaded.attrs<terms>).to.eq(False);
    }
  }
}

describe 'DateTime round-trip through coerce-write / coerce-read', {
  before-each {
    Article.destroy-all;
  }

  after-each {
    Article.destroy-all;
  }

  it 'materializes created_at as DateTime on insert', {
    my $a = Article.create({ title => 'Coercion', body => 'check' });
    expect($a.attrs<created_at>).to.be-a(DateTime);
  }

  it 'reads created_at back as DateTime', {
    my $a = Article.create({ title => 'Coercion', body => 'check' });
    my $found-a = Article.find($a.id);
    expect($found-a.attrs<created_at>).to.be-a(DateTime);
  }

  it 'reads updated_at back as DateTime', {
    my $a = Article.create({ title => 'Coercion', body => 'check' });
    my $found-a = Article.find($a.id);
    expect($found-a.attrs<updated_at>).to.be-a(DateTime);
  }

  it 'gives created_at a real epoch value', {
    my $a = Article.create({ title => 'Coercion', body => 'check' });
    my $found-a = Article.find($a.id);
    expect($found-a.attrs<created_at>.posix).to.be-greater-than(0);
  }
}
