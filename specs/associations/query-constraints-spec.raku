use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

class Qcdoc { ... }

class Qcorg is Model {
  submethod BUILD {
    self.has-many: qcdocs => %(
      class             => Qcdoc,
      query-constraints => ['qcorg_id', 'qcuser_id'],
    );
  }
}

class Qcdoc is Model {}

sub qc-clean {
  clean-shared-tables;
}

describe 'has-many with query-constraints', {
  before-each { qc-clean }
  after-each  { qc-clean }

  context 'org A as user 7', {
    it 'returns rows matching both columns', {
      my $org-a = Qcorg.create({name => 'A'});
      my $org-b = Qcorg.create({name => 'B'});
      Qcdoc.create({title => 'a7-1', qcorg_id => $org-a.id, qcuser_id => 7});
      Qcdoc.create({title => 'a7-2', qcorg_id => $org-a.id, qcuser_id => 7});
      Qcdoc.create({title => 'a8-1', qcorg_id => $org-a.id, qcuser_id => 8});
      Qcdoc.create({title => 'b7-1', qcorg_id => $org-b.id, qcuser_id => 7});

      my $a-as-user7 = Qcorg.find($org-a.id);
      $a-as-user7.attrs<qcuser_id> = 7;

      expect($a-as-user7.qcdocs.elems).to.eq(2);
    }

    it 'returns the right two titles', {
      my $org-a = Qcorg.create({name => 'A'});
      Qcdoc.create({title => 'a7-1', qcorg_id => $org-a.id, qcuser_id => 7});
      Qcdoc.create({title => 'a7-2', qcorg_id => $org-a.id, qcuser_id => 7});
      Qcdoc.create({title => 'a8-1', qcorg_id => $org-a.id, qcuser_id => 8});

      my $a-as-user7 = Qcorg.find($org-a.id);
      $a-as-user7.attrs<qcuser_id> = 7;
      my @docs = $a-as-user7.qcdocs.sort({ $_.attrs<title> });

      expect(@docs.map({ $_.attrs<title> }).join(',')).to.eq('a7-1,a7-2');
    }
  }

  it 'picks up a different user_id', {
    my $org-a = Qcorg.create({name => 'A'});
    Qcdoc.create({title => 'a7-1', qcorg_id => $org-a.id, qcuser_id => 7});
    Qcdoc.create({title => 'a8-1', qcorg_id => $org-a.id, qcuser_id => 8});

    my $a-as-user8 = Qcorg.find($org-a.id);
    $a-as-user8.attrs<qcuser_id> = 8;

    expect($a-as-user8.qcdocs.elems).to.eq(1);
  }

  it 'scopes by org too', {
    my $org-a = Qcorg.create({name => 'A'});
    my $org-b = Qcorg.create({name => 'B'});
    Qcdoc.create({title => 'a7-1', qcorg_id => $org-a.id, qcuser_id => 7});
    Qcdoc.create({title => 'b7-1', qcorg_id => $org-b.id, qcuser_id => 7});

    my $b-as-user7 = Qcorg.find($org-b.id);
    $b-as-user7.attrs<qcuser_id> = 7;

    expect($b-as-user7.qcdocs.elems).to.eq(1);
  }

  it 'returns no matching docs for (B, 8)', {
    my $org-b = Qcorg.create({name => 'B'});
    Qcdoc.create({title => 'b7-1', qcorg_id => $org-b.id, qcuser_id => 7});

    my $b-as-user8 = Qcorg.find($org-b.id);
    $b-as-user8.attrs<qcuser_id> = 8;

    expect($b-as-user8.qcdocs.elems).to.eq(0);
  }
}
