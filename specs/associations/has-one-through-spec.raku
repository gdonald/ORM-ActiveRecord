use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Profile;
use Models::Account;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'has-one :through', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  let(:user, { User.create({fname => 'Greg', lname => 'Donald'}) });

  context 'before the join record exists', {
    it 'has a valid user', {
      expect(user.is-valid).to.be-truthy;
    }

    it 'has no account', {
      expect(user.account).to.be-nil;
    }
  }

  context 'with a join profile that links an account', {
    let(:acct, { Account.create({name => 'gdonald'}) });

    let-bang(:prof, { Profile.create({user => user, account => acct, bio => 'Raku enthusiast'}) });

    it 'saves the profile', {
      expect(prof.is-valid).to.be-truthy;
    }

    it 'returns the target record', {
      expect(user.account.defined).to.be-truthy;
    }

    it 'returns the correct record', {
      expect(user.account.id).to.eq(acct.id);
    }
  }
}
