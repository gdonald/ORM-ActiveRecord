use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

class Tnitem { ... }

class Tnshop is Model {
  submethod BUILD {
    self.has-many: tnitems => %(class => Tnitem);
  }
}

class Tnitem is Model {
  submethod BUILD {
    self.belongs-to: tnshop => %(
      class    => Tnshop,
      touch    => 'reviewed_at',
      optional => True,
    );
  }
}

sub tn-clean {
  clean-shared-tables;
}

describe 'belongs-to touch', {
  before-each { tn-clean }
  after-each  { tn-clean }

  it 'bumps parent updated_at on child create', {
    my $shop = Tnshop.create({name => 'main'});
    my $u-orig = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];
    sleep 1.05;
    Tnitem.create({label => 'a', tnshop_id => $shop.id});
    my $u-after = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];

    expect($u-after.Str gt $u-orig.Str).to.be-truthy;
  }

  it 'populates the named touch column', {
    my $shop = Tnshop.create({name => 'main'});
    sleep 1.05;
    Tnitem.create({label => 'a', tnshop_id => $shop.id});
    my $r-after = DB.shared.exec("SELECT reviewed_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];

    expect($r-after.defined).to.be-truthy;
  }

  it 'bumps parent updated_at on child destroy', {
    my $shop = Tnshop.create({name => 'main'});
    sleep 1.05;
    my $item = Tnitem.create({label => 'b', tnshop_id => $shop.id});
    my $u-pre = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];
    sleep 1.05;
    $item.destroy;
    my $u-post = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];

    expect($u-post.Str gt $u-pre.Str).to.be-truthy;
  }

  context 'child update', {
    it 'bumps parent updated_at', {
      my $shop = Tnshop.create({name => 'main'});
      Tnitem.create({label => 'a', tnshop_id => $shop.id});
      sleep 1.05;
      my $item-up = Tnitem.find-by({label => 'a'});
      my $u-pre = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];
      $item-up.update({label => 'a2'});
      my $u-post = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];

      expect($u-post.Str gt $u-pre.Str).to.be-truthy;
    }

    it 'bumps named touch column', {
      my $shop = Tnshop.create({name => 'main'});
      Tnitem.create({label => 'a', tnshop_id => $shop.id});
      sleep 1.05;
      my $item-up = Tnitem.find-by({label => 'a'});
      my $r-pre = DB.shared.exec("SELECT reviewed_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];
      $item-up.update({label => 'a2'});
      my $r-post = DB.shared.exec("SELECT reviewed_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];

      expect($r-post.Str gt $r-pre.Str).to.be-truthy;
    }
  }

  it 'is a no-op when no parent FK', {
    my $orphan = Tnitem.create({label => 'lonely'});

    expect($orphan.id).to.be-greater-than(0);
  }

  it 'update-column bypasses touch', {
    my $shop = Tnshop.create({name => 'main'});
    Tnitem.create({label => 'a', tnshop_id => $shop.id});
    sleep 1.05;
    my $item-up = Tnitem.find-by({label => 'a'});
    my $u-pre = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];
    $item-up.update-column('label', 'a3');
    my $u-post = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop.id)[0][0];

    expect($u-post.Str).to.eq($u-pre.Str);
  }

  it 'reassigning FK bumps the new parent', {
    my $shop-a = Tnshop.create({name => 'A'});
    my $shop-b = Tnshop.create({name => 'B'});
    sleep 1.05;
    my $mover = Tnitem.create({label => 'm', tnshop_id => $shop-a.id});
    my $b-before = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop-b.id)[0][0];
    sleep 1.05;
    $mover.update({tnshop_id => $shop-b.id});
    my $b-after = DB.shared.exec("SELECT updated_at FROM tnshops WHERE id = " ~ $shop-b.id)[0][0];

    expect($b-after.Str gt $b-before.Str).to.be-truthy;
  }
}
