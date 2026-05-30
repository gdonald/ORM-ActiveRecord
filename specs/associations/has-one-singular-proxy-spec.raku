use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Profile;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'has-one singular proxy', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'build-<assoc> with attributes', {
    it 'returns an unsaved record', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $built = $user.build-profile({bio => 'hello'});

      expect($built.id).to.be-falsy;
    }

    it 'sets the foreign key', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $built = $user.build-profile({bio => 'hello'});

      expect($built.attrs<user_id>).to.eq($user.id);
    }

    it 'applies attribute overrides', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $built = $user.build-profile({bio => 'hello'});

      expect($built.attrs<bio>).to.eq('hello');
    }
  }

  context 'build-<assoc> with no arguments', {
    it 'returns an unsaved record', {
      my $user = User.create({fname => 'Jane', lname => 'Roe'});
      my $built = $user.build-profile;

      expect($built.id).to.be-falsy;
    }

    it 'still sets the foreign key', {
      my $user = User.create({fname => 'Jane', lname => 'Roe'});
      my $built = $user.build-profile;

      expect($built.attrs<user_id>).to.eq($user.id);
    }
  }

  context 'create-<assoc>', {
    it 'returns a saved record', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $created = $user.create-profile({bio => 'persisted'});

      expect($created.id).to.be-greater-than(0);
    }

    it 'sets the foreign key', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $created = $user.create-profile({bio => 'persisted'});

      expect($created.attrs<user_id>).to.eq($user.id);
    }

    it 'is visible through the accessor', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $created = $user.create-profile({bio => 'persisted'});

      expect($user.profile.id).to.eq($created.id);
    }
  }

  context 'create-<assoc>-or-die success', {
    it 'returns a saved record', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $forced = $user.create-profile-or-die({bio => 'forced'});

      expect($forced.id).to.be-greater-than(0);
    }

    it 'sets the foreign key', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $forced = $user.create-profile-or-die({bio => 'forced'});

      expect($forced.attrs<user_id>).to.eq($user.id);
    }
  }

  context 'create-<assoc>-or-die failure', {
    it 'raises when the target is invalid', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});

      expect({ $user.create-profile-or-die({}) }).to.raise-error;
    }
  }
}
