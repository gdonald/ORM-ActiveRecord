use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Relation::Query;

%*ENV<DISABLE-SQL-LOG> = True;

class Scarticle  {...}
class Scprofile  {...}
class Sctag      {...}

class Scauthor is Model {
  submethod BUILD {
    self.has-many: scarticles => %(
      class => Scarticle,
      scope => -> $q { $q.where({ :published }) },
    );
    self.has-many: top-articles => %(
      class       => Scarticle,
      foreign-key => 'scauthor_id',
      scope       => -> $q { $q.where({ :published }).order('score').limit(2) },
    );
    self.has-many: by-score => %(
      class       => Scarticle,
      foreign-key => 'scauthor_id',
      scope       => -> $q, $min { $q.where({ score => $min..* }) },
    );
    self.has-one: scprofile => %(
      class => Scprofile,
      scope => -> $q { $q.where({ :visible }) },
    );
  }
}

class Scarticle is Model {
  submethod BUILD {
    self.belongs-to: scauthor => %(
      class => Scauthor,
      scope => -> $q { $q.where({ is_active => True }) },
    );
    self.has-and-belongs-to-many: sctags => %(
      class => Sctag,
      scope => -> $q { $q.where({ :hot }) },
    );
  }
}

class Scprofile is Model {
  submethod BUILD {
    self.belongs-to: scauthor => %(class => Scauthor);
  }
}

class Sctag is Model {}

sub sc-clean {
  clean-shared-tables;
}

describe 'association scope', {
  before-each { sc-clean }
  after-each  { sc-clean }

  context 'block scope on has-many filters by where', {
    it 'returns only published rows', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      Scarticle.create({title => 'low',  score => 1, published => True,  scauthor => $alice});
      Scarticle.create({title => 'mid',  score => 5, published => True,  scauthor => $alice});
      Scarticle.create({title => 'high', score => 9, published => True,  scauthor => $alice});
      Scarticle.create({title => 'wip',  score => 2, published => False, scauthor => $alice});

      expect($alice.scarticles.elems).to.eq(3);
    }

    it 'excludes drafts', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      Scarticle.create({title => 'low',  score => 1, published => True,  scauthor => $alice});
      my $draft = Scarticle.create({title => 'wip', score => 2, published => False, scauthor => $alice});

      expect($alice.scarticles.map({ .id }).Bag{$draft.id}:!exists).to.be-truthy;
    }
  }

  context 'scope with limit', {
    it 'returns two records', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      Scarticle.create({title => 'low',  score => 1, published => True, scauthor => $alice});
      Scarticle.create({title => 'mid',  score => 5, published => True, scauthor => $alice});
      Scarticle.create({title => 'high', score => 9, published => True, scauthor => $alice});

      expect($alice.top-articles.elems).to.eq(2);
    }

    it 'orders by score ASC then limits', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      Scarticle.create({title => 'low',  score => 1, published => True, scauthor => $alice});
      Scarticle.create({title => 'mid',  score => 5, published => True, scauthor => $alice});
      Scarticle.create({title => 'high', score => 9, published => True, scauthor => $alice});

      expect($alice.top-articles.map({ .attrs<title> }).join(',')).to.eq('low,mid');
    }
  }

  context 'argument-taking scope', {
    it 'filters with caller-supplied bound', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      Scarticle.create({title => 'low',  score => 1, published => True, scauthor => $alice});
      Scarticle.create({title => 'mid',  score => 5, published => True, scauthor => $alice});
      Scarticle.create({title => 'high', score => 9, published => True, scauthor => $alice});

      expect($alice.by-score(5).map({ .attrs<title> }).sort.join(',')).to.eq('high,mid');
    }

    it 'reflects different bound', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      Scarticle.create({title => 'low',  score => 1, published => True, scauthor => $alice});
      Scarticle.create({title => 'mid',  score => 5, published => True, scauthor => $alice});
      Scarticle.create({title => 'high', score => 9, published => True, scauthor => $alice});

      expect($alice.by-score(9).map({ .attrs<title> }).join(',')).to.eq('high');
    }
  }

  it 'has-one scope filters by visible', {
    my $alice = Scauthor.create({name => 'Alice', is_active => True});
    my $visible-prof = Scprofile.create({bio => 'pinned', visible => True, scauthor => $alice});
    Scprofile.create({bio => 'hidden', visible => False, scauthor => $alice});

    expect(Scauthor.find($alice.id).scprofile.id).to.eq($visible-prof.id);
  }

  context 'belongs-to scope', {
    it 'hides article whose author is inactive', {
      my $inactive = Scauthor.create({name => 'Zed',   is_active => False});
      my $orphan = Scarticle.create({title => 'orphan', published => True, score => 0, scauthor => $inactive});

      expect(Scarticle.find($orphan.id).scauthor.defined).to.be-falsy;
    }

    it 'still returns active author', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      my $pub-low = Scarticle.create({title => 'low', score => 1, published => True, scauthor => $alice});

      expect(Scarticle.find($pub-low.id).scauthor.defined).to.be-truthy;
    }
  }

  context 'habtm scope', {
    it 'filters out non-hot rows', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      my $pub-low = Scarticle.create({title => 'low', score => 1, published => True, scauthor => $alice});
      my $hot  = Sctag.create({name => 'raku', hot => True});
      my $cool = Sctag.create({name => 'old',  hot => False});
      $pub-low.add-sctag($hot);
      $pub-low.add-sctag($cool);

      expect(Scarticle.find($pub-low.id).sctags.elems).to.eq(1);
    }

    it 'returns matching row', {
      my $alice = Scauthor.create({name => 'Alice', is_active => True});
      my $pub-low = Scarticle.create({title => 'low', score => 1, published => True, scauthor => $alice});
      my $hot  = Sctag.create({name => 'raku', hot => True});
      my $cool = Sctag.create({name => 'old',  hot => False});
      $pub-low.add-sctag($hot);
      $pub-low.add-sctag($cool);

      expect(Scarticle.find($pub-low.id).sctags.first.attrs<name>).to.eq('raku');
    }
  }
}
