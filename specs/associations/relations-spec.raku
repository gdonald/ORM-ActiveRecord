use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'relation chaining', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  sub seed {
    my %h;
    %h<alice> = User.create({fname => 'Alice', lname => 'Anderson'});
    %h<bob>   = User.create({fname => 'Bob',   lname => 'Brown'});
    %h<carol> = User.create({fname => 'Carol', lname => 'Crane'});
    %h<dave>  = User.create({fname => 'Dave',  lname => 'Davis'});
    %h<eve>   = User.create({fname => 'Eve',   lname => 'Edwards'});
    %h;
  }

  it 'Model.all returns every row', {
    seed;
    expect(User.all.all.elems).to.eq(5);
  }

  context 'order', {
    it 'returns the right number of rows', {
      seed;
      expect(User.order('fname').all.elems).to.eq(5);
    }

    it 'ascending puts Alice first', {
      seed;
      expect(User.order('fname').all[0].fname).to.eq('Alice');
    }

    it 'ascending puts Eve last', {
      seed;
      expect(User.order('fname').all[*-1].fname).to.eq('Eve');
    }

    it 'DESC reverses', {
      seed;
      expect(User.order('fname DESC').all[0].fname).to.eq('Eve');
    }
  }

  context 'limit', {
    it 'returns the requested number of rows', {
      seed;
      expect(User.order('id').limit(2).all.elems).to.eq(2);
    }

    it 'respects order', {
      my %h = seed;
      expect(User.order('id').limit(2).all[0].id).to.eq(%h<alice>.id);
    }
  }

  context 'offset', {
    it 'returns the requested number of rows', {
      seed;
      expect(User.order('id').limit(2).offset(2).all.elems).to.eq(2);
    }

    it 'starts at the third row', {
      my %h = seed;
      expect(User.order('id').limit(2).offset(2).all[0].id).to.eq(%h<carol>.id);
    }
  }

  context 'chained where + order + limit', {
    it 'returns one row', {
      seed;
      expect(User.where({lname => 'Crane'}).order('id').limit(1).all.elems).to.eq(1);
    }

    it 'returns Carol', {
      seed;
      expect(User.where({lname => 'Crane'}).order('id').limit(1).all[0].fname).to.eq('Carol');
    }
  }

  context 'Query.where chained from .all', {
    it 'narrows the result', {
      seed;
      expect(User.all.where({fname => 'Bob'}).all.elems).to.eq(1);
    }

    it 'matches Bob', {
      my %h = seed;
      expect(User.all.where({fname => 'Bob'}).all[0].id).to.eq(%h<bob>.id);
    }
  }

  it 'pluck single column returns ordered list', {
    seed;
    expect(User.order('fname').pluck('fname').join(',')).to.eq('Alice,Bob,Carol,Dave,Eve');
  }

  it 'pluck multi returns row tuples', {
    seed;
    expect(User.order('id').limit(2).pluck('fname', 'lname')[0].join(' ')).to.eq('Alice Anderson');
  }

  it 'ids returns id column in order', {
    my %h = seed;
    my @expected = (%h<alice>.id, %h<bob>.id, %h<carol>.id, %h<dave>.id, %h<eve>.id);
    expect(User.order('id').ids.join(',')).to.eq(@expected.join(','));
  }
}
