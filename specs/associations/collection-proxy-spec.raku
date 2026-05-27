use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class Cppost { ... }
class Cpcomment { ... }

role CpostsExtension {
  method high-score(Int:D $n) {
    self.records.grep({ .attrs<score> >= $n });
  }
  method by-title {
    self.records.sort({ .attrs<title> });
  }
}

class Cpauthor is Model {
  submethod BUILD {
    self.has-many: cpposts => %(
      class     => Cppost,
      extension => CpostsExtension,
    );
    self.has-many: cpcomments => %(
      class => Cpcomment,
      as    => 'commentable',
    );
  }
}

class Cppost is Model {
  submethod BUILD {
    self.belongs-to: cpauthor => class => Cpauthor;
  }
}

class Cpcomment is Model {
  submethod BUILD {
    self.belongs-to: commentable => polymorphic => True;
  }
}

sub cp-clean {
  clean-shared-tables;
}

describe 'collection proxy', {
  before-each { cp-clean }
  after-each  { cp-clean }

  context 'build', {
    it 'returns an unsaved record', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $built = $alice.cpposts.build({title => 'draft', body => 'd'});
      expect($built.id).to.be-falsy;
    }

    it 'sets the foreign key', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $built = $alice.cpposts.build({title => 'draft', body => 'd'});
      expect($built.attrs<cpauthor_id>).to.eq($alice.id);
    }
  }

  context 'create', {
    it 'returns a saved record', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $created = $alice.cpposts.create({title => 'live', body => 'b', score => 10});
      expect($created.id).to.be-greater-than(0);
    }

    it 'sets the foreign key', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $created = $alice.cpposts.create({title => 'live', body => 'b', score => 10});
      expect($created.attrs<cpauthor_id>).to.eq($alice.id);
    }
  }

  context 'create-or-die', {
    it 'returns a saved record', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $forced = $alice.cpposts.create-or-die({title => 'forced', body => 'b'});
      expect($forced.id).to.be-greater-than(0);
    }

    it 'sets the foreign key', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $forced = $alice.cpposts.create-or-die({title => 'forced', body => 'b'});
      expect($forced.attrs<cpauthor_id>).to.eq($alice.id);
    }
  }

  context 'push / append', {
    it 'orphan has no author before push', {
      Cpauthor.create({name => 'alice'});
      my $orphan = Cppost.create({title => 'orphan', body => 'o'});
      expect($orphan.attrs<cpauthor_id>).to.eq(0);
    }

    it 'push sets the foreign key', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $orphan = Cppost.create({title => 'orphan', body => 'o'});
      $alice.cpposts.push($orphan);
      my $reloaded = Cppost.find($orphan.id);
      expect($reloaded.attrs<cpauthor_id>).to.eq($alice.id);
    }

    it 'pushed records are visible on reload', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $orphan = Cppost.create({title => 'orphan', body => 'o'});
      $alice.cpposts.push($orphan);
      my $b = Cppost.create({title => 'b', body => 'b'});
      my $c = Cppost.create({title => 'c', body => 'c'});
      $alice.cpposts.append($b);
      $alice.cpposts.push($c);

      expect($alice.cpposts.elems).to.eq(3);
    }
  }

  context 'delete / destroy / clear', {
    it 'starts with three children', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'p1', body => 'b'});
      $alice.cpposts.create({title => 'p2', body => 'b'});
      $alice.cpposts.create({title => 'p3', body => 'b'});

      expect($alice.cpposts.elems).to.eq(3);
    }

    it 'delete nullifies FK but keeps row', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $p1 = $alice.cpposts.create({title => 'p1', body => 'b'});
      $alice.cpposts.delete($p1);
      my $nullified = Cppost.find($p1.id);

      expect($nullified.attrs<cpauthor_id>).to.be-falsy;
    }

    it 'collection drops the deleted record', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $p1 = $alice.cpposts.create({title => 'p1', body => 'b'});
      $alice.cpposts.create({title => 'p2', body => 'b'});
      $alice.cpposts.delete($p1);

      expect($alice.cpposts.elems).to.eq(1);
    }

    it 'destroy actually removes the row', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $p2 = $alice.cpposts.create({title => 'p2', body => 'b'});
      $alice.cpposts.destroy($p2);

      expect(Cppost.where({id => $p2.id}).count).to.eq(0);
    }

    it 'clear empties the collection', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'p3', body => 'b'});
      $alice.cpposts.clear;

      expect($alice.cpposts.elems).to.eq(0);
    }

    it 'clear leaves the row in place', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $p3 = $alice.cpposts.create({title => 'p3', body => 'b'});
      $alice.cpposts.clear;

      expect(Cppost.where({id => $p3.id}).first.defined).to.be-truthy;
    }
  }

  context 'is-empty / size / count / length', {
    it 'is-empty true on fresh association', {
      my $alice = Cpauthor.create({name => 'alice'});
      expect($alice.cpposts.is-empty).to.be-truthy;
    }

    it 'size is 0 on fresh association', {
      my $alice = Cpauthor.create({name => 'alice'});
      expect($alice.cpposts.size).to.eq(0);
    }

    it 'count is 0 on fresh association', {
      my $alice = Cpauthor.create({name => 'alice'});
      expect($alice.cpposts.count).to.eq(0);
    }

    it 'length is 0 on fresh association', {
      my $alice = Cpauthor.create({name => 'alice'});
      expect($alice.cpposts.length).to.eq(0);
    }

    it 'is-empty false after creates', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'a', body => 'b'});
      $alice.cpposts.create({title => 'c', body => 'd'});
      expect($alice.cpposts.is-empty).to.be-falsy;
    }

    it 'size matches', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'a', body => 'b'});
      $alice.cpposts.create({title => 'c', body => 'd'});
      expect($alice.cpposts.size).to.eq(2);
    }

    it 'count matches', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'a', body => 'b'});
      $alice.cpposts.create({title => 'c', body => 'd'});
      expect($alice.cpposts.count).to.eq(2);
    }

    it 'length matches', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'a', body => 'b'});
      $alice.cpposts.create({title => 'c', body => 'd'});
      expect($alice.cpposts.length).to.eq(2);
    }
  }

  context 'exists / find', {
    it 'exists() returns True with members', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'a', body => 'b'});
      expect($alice.cpposts.exists).to.be-truthy;
    }

    it 'exists(id) finds a member', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $p1 = $alice.cpposts.create({title => 'a', body => 'b'});
      expect($alice.cpposts.exists($p1.id)).to.be-truthy;
    }

    it 'exists(unknown-id) is False', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'a', body => 'b'});
      expect($alice.cpposts.exists(9999)).to.be-falsy;
    }

    it 'exists(hash) matches by attrs', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'a', body => 'b'});
      expect($alice.cpposts.exists({title => 'a'})).to.be-truthy;
    }

    it 'exists(hash) misses unknown attrs', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'a', body => 'b'});
      expect($alice.cpposts.exists({title => 'missing'})).to.be-falsy;
    }

    it 'find(id) returns the matching record', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $p2 = $alice.cpposts.create({title => 'c', body => 'd'});
      expect($alice.cpposts.find($p2.id).attrs<title>).to.eq('c');
    }

    it 'find(unknown-id) raises', {
      my $alice = Cpauthor.create({name => 'alice'});
      expect({ $alice.cpposts.find(9999) }).to.raise-error;
    }
  }

  context 'replace', {
    it 'leaves only the new set', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $keep   = $alice.cpposts.create({title => 'keep', body => 'b'});
      $alice.cpposts.create({title => 'd1', body => 'b'});
      $alice.cpposts.create({title => 'd2', body => 'b'});
      my $newone = Cppost.create({title => 'new', body => 'b'});
      $alice.cpposts.replace([$keep, $newone]);

      expect($alice.cpposts.list.elems).to.eq(2);
    }

    it 'contains exactly the requested rows', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $keep   = $alice.cpposts.create({title => 'keep', body => 'b'});
      $alice.cpposts.create({title => 'd1', body => 'b'});
      my $newone = Cppost.create({title => 'new', body => 'b'});
      $alice.cpposts.replace([$keep, $newone]);

      expect($alice.cpposts.list.sort({ .attrs<title> }).map({ .attrs<title> }).sort.join(',')).to.eq('keep,new');
    }

    it 'nullifies first dropped row', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $keep   = $alice.cpposts.create({title => 'keep', body => 'b'});
      my $drop1  = $alice.cpposts.create({title => 'd1', body => 'b'});
      $alice.cpposts.create({title => 'd2', body => 'b'});
      my $newone = Cppost.create({title => 'new', body => 'b'});
      $alice.cpposts.replace([$keep, $newone]);

      expect(Cppost.find($drop1.id).attrs<cpauthor_id>).to.be-falsy;
    }

    it 'nullifies other dropped rows', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $keep   = $alice.cpposts.create({title => 'keep', body => 'b'});
      $alice.cpposts.create({title => 'd1', body => 'b'});
      my $drop2  = $alice.cpposts.create({title => 'd2', body => 'b'});
      my $newone = Cppost.create({title => 'new', body => 'b'});
      $alice.cpposts.replace([$keep, $newone]);

      expect(Cppost.find($drop2.id).attrs<cpauthor_id>).to.be-falsy;
    }
  }

  context 'association extension role', {
    it 'high-score returns matches', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'low',  body => '', score => 1});
      $alice.cpposts.create({title => 'mid',  body => '', score => 5});
      $alice.cpposts.create({title => 'high', body => '', score => 9});

      expect($alice.cpposts.high-score(5).elems).to.eq(2);
    }

    it 'high-score picks the right rows', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'low',  body => '', score => 1});
      $alice.cpposts.create({title => 'mid',  body => '', score => 5});
      $alice.cpposts.create({title => 'high', body => '', score => 9});

      expect($alice.cpposts.high-score(5).map({ .attrs<title> }).sort.join(',')).to.eq('high,mid');
    }

    it 'by-title sorts via the underlying records', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpposts.create({title => 'low',  body => '', score => 1});
      $alice.cpposts.create({title => 'mid',  body => '', score => 5});
      $alice.cpposts.create({title => 'high', body => '', score => 9});

      expect($alice.cpposts.by-title.map({ .attrs<title> }).join(',')).to.eq('high,low,mid');
    }
  }

  context 'polymorphic has-many proxy', {
    it 'sets <as>_id', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $c1 = $alice.cpcomments.create({body => 'first'});
      expect($c1.attrs<commentable_id>).to.eq($alice.id);
    }

    it 'sets <as>_type', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $c1 = $alice.cpcomments.create({body => 'first'});
      expect($c1.attrs<commentable_type>).to.eq('Cpauthor');
    }

    it 'collection size', {
      my $alice = Cpauthor.create({name => 'alice'});
      $alice.cpcomments.create({body => 'first'});
      $alice.cpcomments.create({body => 'second'});
      expect($alice.cpcomments.size).to.eq(2);
    }

    it 'delete nullifies <as>_id', {
      my $alice = Cpauthor.create({name => 'alice'});
      my $c1 = $alice.cpcomments.create({body => 'first'});
      $alice.cpcomments.create({body => 'second'});
      $alice.cpcomments.delete($c1);
      my $reloaded = Cpcomment.find($c1.id);

      expect($reloaded.attrs<commentable_id>).to.be-falsy;
    }
  }
}
