use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::UniquenessConditions;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'uniqueness with conditions', {
  before-each { PhuserActive.destroy-all }
  after-each  { PhuserScopeCond.destroy-all }

  context 'conditions narrow lookup to a subset', {
    it 'allows duplicate when existing record fails the conditions', {
      PhuserActive.create({username => 'inactive_dupe', is_active => False, tenant_id => 1});
      my $ok = PhuserActive.build({username => 'inactive_dupe', is_active => True, tenant_id => 1});
      expect($ok.is-valid).to.be-truthy;
    }

    it 'rejects duplicate within the active scope', {
      PhuserActive.create({username => 'active_user', is_active => True, tenant_id => 1});
      my $clash = PhuserActive.build({username => 'active_user', is_active => True, tenant_id => 2});
      expect($clash.is-invalid).to.be-truthy;
    }

    it 'reports "must be unique"', {
      PhuserActive.create({username => 'active_user', is_active => True, tenant_id => 1});
      my $clash = PhuserActive.build({username => 'active_user', is_active => True, tenant_id => 2});
      $clash.is-invalid;
      expect($clash.errors.username[0]).to.eq('must be unique');
    }
  }

  context 'conditions combine with scope', {
    before-each {
      PhuserActive.destroy-all;
      PhuserScopeCond.destroy-all;
      PhuserScopeCond.create({username => 'shared', is_active => True, tenant_id => 1});
    }

    it 'allows the same name in a different tenant', {
      my $other = PhuserScopeCond.build({username => 'shared', is_active => True, tenant_id => 2});
      expect($other.is-valid).to.be-truthy;
    }

    it 'rejects the same name + tenant + active', {
      my $same = PhuserScopeCond.build({username => 'shared', is_active => True, tenant_id => 1});
      expect($same.is-invalid).to.be-truthy;
    }

    it 'ignores inactive records within the same scope', {
      PhuserScopeCond.create({username => 'inactive_in_scope', is_active => False, tenant_id => 1});
      my $allow = PhuserScopeCond.build({username => 'inactive_in_scope', is_active => False, tenant_id => 1});
      expect($allow.is-valid).to.be-truthy;
    }

    it 'allows promoting a name that has no active record yet', {
      PhuserScopeCond.create({username => 'inactive_in_scope', is_active => False, tenant_id => 1});
      my $promote = PhuserScopeCond.build({username => 'inactive_in_scope', is_active => True, tenant_id => 1});
      expect($promote.is-valid).to.be-truthy;
    }
  }
}
