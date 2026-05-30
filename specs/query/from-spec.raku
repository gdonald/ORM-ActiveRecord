use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'from', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    User.destroy-all;
  }

  it 'from-source is undef by default', {
    expect(User.all.from-source.defined).to.be-falsy;
  }

  context 'from(users) acts identically to the default', {
    it 'counts all rows', {
      expect(User.from('users').count).to.eq(3);
    }

    it 'returns all rows', {
      expect(User.from('users').all.elems).to.eq(3);
    }
  }

  context 'from(subquery aliased as users)', {
    it 'filters rows', {
      my @rows = User.from('(SELECT * FROM users WHERE lname != ' ~ "'Brown') users").all;

      expect(@rows.elems).to.eq(2);
    }

    it 'no Brown survived the subquery filter', {
      my @rows = User.from('(SELECT * FROM users WHERE lname != ' ~ "'Brown') users").all;

      expect((none @rows.map: { .lname eq 'Brown' }).Bool).to.be-truthy;
    }
  }

  context 'from with explicit alias', {
    it 'captures the from-alias', {
      my $q = User.from('users AS u', 'u');

      expect($q.from-alias).to.eq('u');
    }

    it 'count works with aliased from', {
      my $q = User.from('users AS u', 'u');

      expect($q.count).to.eq(3);
    }
  }

  it 'unscope(:from) clears the source', {
    expect(User.from('(SELECT 1) sub').unscope(:from).from-source.WHAT === Str).to.be-truthy;
  }
}
