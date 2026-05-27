use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class GhUser is Model {
  method table-name { 'users' }
}

describe 'group / having', {
  before-each {
    GhUser.destroy-all;
    GhUser.create({fname => 'Alice', lname => 'Anderson'});
    GhUser.create({fname => 'Adam',  lname => 'Anderson'});
    GhUser.create({fname => 'Bob',   lname => 'Brown'});
    GhUser.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    GhUser.destroy-all;
  }

  context 'group + count', {
    it 'returns 3 entries', {
      my %g = GhUser.group('lname').count;

      expect(%g.elems).to.eq(3);
    }

    it 'tallies per group', {
      my %g = GhUser.group('lname').count;

      expect(%g<Anderson> == 2 && %g<Brown> == 1 && %g<Carter> == 1).to.be-truthy;
    }
  }

  context 'group + pluck', {
    it 'returns 3 rows', {
      my @lnames = GhUser.group('lname').pluck('lname').sort;

      expect(@lnames.elems).to.eq(3);
    }

    it 'returns each group', {
      my @lnames = GhUser.group('lname').pluck('lname').sort;

      expect(@lnames.join(',')).to.eq('Anderson,Brown,Carter');
    }
  }

  context 'raw having clause', {
    it 'filters to 1 group via count', {
      my %big-h = GhUser.group('lname').having('count(*) > 1').count;

      expect(%big-h.elems == 1 && %big-h<Anderson> == 2).to.be-truthy;
    }

    it 'kept the > 1 group via pluck', {
      my @big = GhUser.group('lname').having('count(*) > 1').pluck('lname');

      expect(@big.elems == 1 && @big[0] eq 'Anderson').to.be-truthy;
    }
  }

  context 'parameterised having', {
    it 'having with bind > 0 keeps all', {
      expect(GhUser.group('lname').having('count(*) > ?', 0).count.elems).to.eq(3);
    }

    it 'having with bind > 1 keeps Anderson', {
      expect(GhUser.group('lname').having('count(*) > ?', 1).count.elems).to.eq(1);
    }
  }

  context 'unscope', {
    it 'unscope(:group) drops grouping', {
      expect(GhUser.group('lname').unscope(:group).all.elems).to.eq(4);
    }

    it 'unscope(:having) drops the filter', {
      expect(GhUser.group('lname').having('count(*) > 1').unscope(:having).count.elems).to.eq(3);
    }
  }

  context 'merge propagates group / having', {
    it 'merge propagates group', {
      my $q1 = GhUser.where({lname => 'Anderson'});
      my $q2 = GhUser.group('lname');
      my @gq = $q1.merge($q2).group-values;

      expect(@gq.join(',')).to.eq('lname');
    }

    it 'merged group + where keeps one group', {
      expect(GhUser.where({lname => 'Anderson'}).merge(GhUser.group('lname')).count.elems).to.eq(1);
    }
  }

  it 'where + group counts groups within scope', {
    expect(GhUser.where({lname => 'Anderson'}).group('lname').count.elems).to.eq(1);
  }
}
