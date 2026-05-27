use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class HspProfile {...}

class HspUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-one: hspprofile => %(class => HspProfile, foreign-key => 'user_id');
  }
}

class HspProfile is Model {
  method table-name { 'profiles' }

  submethod BUILD {
    self.belongs-to: hspuser => %(class => HspUser, foreign-key => 'user_id');
    self.validate: 'bio', { :presence };
  }
}

describe 'has-one singular proxy', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'build-<assoc> with attributes', {
    it 'returns an unsaved record', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});
      my $built = $user.build-hspprofile({bio => 'hello'});

      expect($built.id).to.be-falsy;
    }

    it 'sets the foreign key', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});
      my $built = $user.build-hspprofile({bio => 'hello'});

      expect($built.attrs<user_id>).to.eq($user.id);
    }

    it 'applies attribute overrides', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});
      my $built = $user.build-hspprofile({bio => 'hello'});

      expect($built.attrs<bio>).to.eq('hello');
    }
  }

  context 'build-<assoc> with no arguments', {
    it 'returns an unsaved record', {
      my $user = HspUser.create({fname => 'Jane', lname => 'Roe'});
      my $built = $user.build-hspprofile;

      expect($built.id).to.be-falsy;
    }

    it 'still sets the foreign key', {
      my $user = HspUser.create({fname => 'Jane', lname => 'Roe'});
      my $built = $user.build-hspprofile;

      expect($built.attrs<user_id>).to.eq($user.id);
    }
  }

  context 'create-<assoc>', {
    it 'returns a saved record', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});
      my $created = $user.create-hspprofile({bio => 'persisted'});

      expect($created.id).to.be-greater-than(0);
    }

    it 'sets the foreign key', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});
      my $created = $user.create-hspprofile({bio => 'persisted'});

      expect($created.attrs<user_id>).to.eq($user.id);
    }

    it 'is visible through the accessor', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});
      my $created = $user.create-hspprofile({bio => 'persisted'});

      expect($user.hspprofile.id).to.eq($created.id);
    }
  }

  context 'create-<assoc>-or-die success', {
    it 'returns a saved record', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});
      my $forced = $user.create-hspprofile-or-die({bio => 'forced'});

      expect($forced.id).to.be-greater-than(0);
    }

    it 'sets the foreign key', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});
      my $forced = $user.create-hspprofile-or-die({bio => 'forced'});

      expect($forced.attrs<user_id>).to.eq($user.id);
    }
  }

  context 'create-<assoc>-or-die failure', {
    it 'raises when the target is invalid', {
      my $user = HspUser.create({fname => 'Greg', lname => 'Donald'});

      expect({ $user.create-hspprofile-or-die({}) }).to.raise-error;
    }
  }
}
