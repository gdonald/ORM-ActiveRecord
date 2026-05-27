use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class FmUser is Model {
  method table-name { 'users' }
}

describe 'from', {
  before-each {
    FmUser.destroy-all;
    FmUser.create({fname => 'Alice', lname => 'Anderson'});
    FmUser.create({fname => 'Bob',   lname => 'Brown'});
    FmUser.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    FmUser.destroy-all;
  }

  it 'from-source is undef by default', {
    expect(FmUser.all.from-source.defined).to.be-falsy;
  }

  context 'from(users) acts identically to the default', {
    it 'counts all rows', {
      expect(FmUser.from('users').count).to.eq(3);
    }

    it 'returns all rows', {
      expect(FmUser.from('users').all.elems).to.eq(3);
    }
  }

  context 'from(subquery aliased as users)', {
    it 'filters rows', {
      my @rows = FmUser.from('(SELECT * FROM users WHERE lname != ' ~ "'Brown') users").all;

      expect(@rows.elems).to.eq(2);
    }

    it 'no Brown survived the subquery filter', {
      my @rows = FmUser.from('(SELECT * FROM users WHERE lname != ' ~ "'Brown') users").all;

      expect((none @rows.map: { .lname eq 'Brown' }).Bool).to.be-truthy;
    }
  }

  context 'from with explicit alias', {
    it 'captures the from-alias', {
      my $q = FmUser.from('users AS u', 'u');

      expect($q.from-alias).to.eq('u');
    }

    it 'count works with aliased from', {
      my $q = FmUser.from('users AS u', 'u');

      expect($q.count).to.eq(3);
    }
  }

  it 'unscope(:from) clears the source', {
    expect(FmUser.from('(SELECT 1) sub').unscope(:from).from-source.WHAT === Str).to.be-truthy;
  }
}
