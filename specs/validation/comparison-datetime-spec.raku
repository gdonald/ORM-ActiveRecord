use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::ComparisonDatetime;

%*ENV<DISABLE-SQL-LOG> = True;

my $start    = DateTime.new('2026-06-01T10:00:00Z');
my $end-good = DateTime.new('2026-06-01T12:00:00Z');
my $end-bad  = DateTime.new('2026-06-01T08:00:00Z');

describe 'comparison validator with DateTime values', {
  before-each { Phdt.destroy-all }
  after-each  { Phdt.destroy-all }

  context 'ends_at after starts_at', {
    it 'is valid', {
      my $d = Phdt.build({name => 'E', starts_at => $start, ends_at => $end-good});
      expect($d.is-valid).to.be-truthy;
    }
  }

  context 'ends_at before starts_at', {
    it 'is invalid', {
      my $d = Phdt.build({name => 'E', starts_at => $start, ends_at => $end-bad});
      expect($d.is-invalid).to.be-truthy;
    }

    it 'names the other attribute in the gt message', {
      my $d = Phdt.build({name => 'E', starts_at => $start, ends_at => $end-bad});
      $d.is-invalid;
      expect($d.errors.ends_at[0]).to.eq('must be greater than starts_at');
    }
  }

  context 'equal datetimes', {
    it 'fail strict gt', {
      my $d = Phdt.build({name => 'E', starts_at => $start, ends_at => $start});
      expect($d.is-invalid).to.be-truthy;
    }
  }

  context 'literal datetime cutoff via gte', {
    it 'is valid when at or after cutoff', {
      my $lit = PhdtLit.build({name => 'L', starts_at => DateTime.new('2026-02-01T00:00:00Z'), ends_at => $end-good});
      expect($lit.is-valid).to.be-truthy;
    }

    it 'is invalid when before cutoff', {
      my $lit = PhdtLit.build({name => 'L', starts_at => DateTime.new('2025-12-31T23:59:59Z'), ends_at => $end-good});
      expect($lit.is-invalid).to.be-truthy;
    }
  }
}
