use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

class Thsub { ... }
class Thmag { ... }

class Thuser is Model {
  submethod BUILD {
    self.has-many: thsubs => %(class => Thsub);
    self.has-many: subscribed-mags => %(
      class   => Thmag,
      through => :thsubs,
      source  => :thmag,
    );
    self.has-many: dj-mags => %(
      class         => Thmag,
      through       => :thsubs,
      source        => :thmag,
      disable-joins => True,
    );
  }
}

class Thmag is Model {
  submethod BUILD {
    self.has-many: thsubs => %(class => Thsub);
    self.has-many: thusers => %(
      class   => Thuser,
      through => :thsubs,
    );
  }
}

class Thsub is Model {
  submethod BUILD {
    self.belongs-to: thuser => %(class => Thuser);
    self.belongs-to: thmag  => %(class => Thmag);
  }
}

sub th-clean {
  clean-shared-tables;
}

describe 'has-many :through with source and disable-joins', {
  before-each { th-clean }
  after-each  { th-clean }

  it 'baseline has-many through resolves', {
    my $user = Thuser.create({name => 'Greg'});
    my $mag-a = Thmag.create({title => 'A'});
    my $mag-b = Thmag.create({title => 'B'});
    Thsub.create({thuser => $user, thmag => $mag-a});
    Thsub.create({thuser => $user, thmag => $mag-b});

    expect($user.thsubs.map({ $_.attrs<thmag_id> }).sort.elems).to.eq(2);
  }

  context 'source: alias', {
    it 'resolves through-target', {
      my $user = Thuser.create({name => 'Greg'});
      my $mag-a = Thmag.create({title => 'A'});
      my $mag-b = Thmag.create({title => 'B'});
      Thsub.create({thuser => $user, thmag => $mag-a});
      Thsub.create({thuser => $user, thmag => $mag-b});

      expect($user.subscribed-mags.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my $user = Thuser.create({name => 'Greg'});
      my $mag-a = Thmag.create({title => 'A'});
      my $mag-b = Thmag.create({title => 'B'});
      Thsub.create({thuser => $user, thmag => $mag-a});
      Thsub.create({thuser => $user, thmag => $mag-b});

      expect($user.subscribed-mags.map({ $_.attrs<title> }).sort.join(',')).to.eq('A,B');
    }
  }

  context 'disable-joins', {
    it 'returns the correct number of rows', {
      my $user = Thuser.create({name => 'Greg'});
      my $mag-a = Thmag.create({title => 'A'});
      my $mag-b = Thmag.create({title => 'B'});
      Thsub.create({thuser => $user, thmag => $mag-a});
      Thsub.create({thuser => $user, thmag => $mag-b});

      expect($user.dj-mags.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my $user = Thuser.create({name => 'Greg'});
      my $mag-a = Thmag.create({title => 'A'});
      my $mag-b = Thmag.create({title => 'B'});
      Thsub.create({thuser => $user, thmag => $mag-a});
      Thsub.create({thuser => $user, thmag => $mag-b});

      expect($user.dj-mags.map({ $_.attrs<title> }).sort.join(',')).to.eq('A,B');
    }

    it 'returns an empty list when there are no through-rows', {
      my $lonely = Thuser.create({name => 'Lonely'});
      expect($lonely.dj-mags.elems).to.eq(0);
    }
  }
}
