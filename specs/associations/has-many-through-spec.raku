use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class HmtSubscription {...}

class HmtUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-many: subscriptions => %(class => HmtSubscription, foreign-key => 'user_id');
    self.has-many: magazines      => %(through => :subscriptions);
  }
}

class HmtMagazine is Model {
  method table-name { 'magazines' }
  method fkey-name  { 'magazine_id' }
}

class HmtSubscription is Model {
  method table-name { 'subscriptions' }

  submethod BUILD {
    self.belongs-to: hmtuser     => %(class => HmtUser,     foreign-key => 'user_id');
    self.belongs-to: magazine    => %(class => HmtMagazine, foreign-key => 'magazine_id');
  }
}

describe 'has-many :through', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'returns the joined record through the join model', {
    my $user = HmtUser.create({fname => 'Greg'});
    my $mag  = HmtMagazine.create({title => 'Mad'});
    HmtSubscription.create({hmtuser => $user, magazine => $mag});

    expect($user.magazines.first.id).to.eq($mag.id);
  }
}
