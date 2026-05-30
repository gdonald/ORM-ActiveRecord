use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Profile;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'has-one', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'before the associated record exists', {
    it 'saves the parent user', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'returns Nil for the missing has-one', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      expect($user.profile).to.be-nil;
    }
  }

  context 'when the associated record exists', {
    it 'saves the associated profile', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $profile = Profile.create({user => $user, bio => 'Raku enthusiast'});

      expect($profile.is-valid).to.be-truthy;
    }

    it 'returns a defined record from has-one', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      Profile.create({user => $user, bio => 'Raku enthusiast'});

      expect($user.profile.defined).to.be-truthy;
    }

    it 'returns the correct associated record', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $profile = Profile.create({user => $user, bio => 'Raku enthusiast'});

      expect($user.profile.id).to.eq($profile.id);
    }
  }
}
