use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class UscSubscription {...}

class UscUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-many: subscriptions => class => UscSubscription;

    self.validate: 'fname', { :presence }
  }
}

class UscMagazine is Model {
  method table-name { 'magazines' }

  submethod BUILD {
    self.has-many: subscriptions => class => UscSubscription;

    self.validate: 'title', { :presence }
  }
}

class UscSubscription is Model {
  method table-name { 'subscriptions' }

  submethod BUILD {
    self.belongs-to: user => class => UscUser;
    self.belongs-to: magazine => class => UscMagazine;

    self.validate: 'user_id', { uniqueness => scope => :magazine_id }
  }
}

sub clean {
  UscSubscription.destroy-all;
  UscMagazine.destroy-all;
  UscUser.destroy-all;
}

describe 'uniqueness with scope', {
  before-each { clean }
  after-each  { clean }

  context 'first subscription for a (user, magazine) pair', {
    it 'is valid', {
      my $user     = UscUser.create({fname => 'Greg'});
      my $magazine = UscMagazine.create({title => 'Mad'});
      my $sub      = UscSubscription.create({:$user, :$magazine});
      expect($sub.is-valid).to.be-truthy;
    }
  }

  context 'second subscription for the same pair', {
    it 'is invalid', {
      my $user     = UscUser.create({fname => 'Greg'});
      my $magazine = UscMagazine.create({title => 'Mad'});
      UscSubscription.create({:$user, :$magazine});
      my $sub      = UscSubscription.build({:$user, :$magazine});
      expect($sub.is-valid).to.be-falsy;
    }

    it 'reports "must be unique" on user_id', {
      my $user     = UscUser.create({fname => 'Greg'});
      my $magazine = UscMagazine.create({title => 'Mad'});
      UscSubscription.create({:$user, :$magazine});
      my $sub      = UscSubscription.build({:$user, :$magazine});
      $sub.is-valid;
      expect($sub.errors.user_id[0]).to.eq('must be unique');
    }
  }
}
