use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class HoProfile {...}

class HoUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-one: hoprofile => %(class => HoProfile, foreign-key => 'user_id');
  }
}

class HoProfile is Model {
  method table-name { 'profiles' }

  submethod BUILD {
    self.belongs-to: houser => %(class => HoUser, foreign-key => 'user_id');
  }
}

describe 'has-one', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'before the associated record exists', {
    it 'saves the parent user', {
      my $user = HoUser.create({fname => 'Greg', lname => 'Donald'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'returns Nil for the missing has-one', {
      my $user = HoUser.create({fname => 'Greg', lname => 'Donald'});
      expect($user.hoprofile).to.be-nil;
    }
  }

  context 'when the associated record exists', {
    it 'saves the associated profile', {
      my $user = HoUser.create({fname => 'Greg', lname => 'Donald'});
      my $profile = HoProfile.create({houser => $user, bio => 'Raku enthusiast'});

      expect($profile.is-valid).to.be-truthy;
    }

    it 'returns a defined record from has-one', {
      my $user = HoUser.create({fname => 'Greg', lname => 'Donald'});
      HoProfile.create({houser => $user, bio => 'Raku enthusiast'});

      expect($user.hoprofile.defined).to.be-truthy;
    }

    it 'returns the correct associated record', {
      my $user = HoUser.create({fname => 'Greg', lname => 'Donald'});
      my $profile = HoProfile.create({houser => $user, bio => 'Raku enthusiast'});

      expect($user.hoprofile.id).to.eq($profile.id);
    }
  }
}
