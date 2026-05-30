use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Errors::X;
use Models::User;
use Models::Article;
use Models::Comment;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'collection proxy', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'build', {
    it 'returns an unsaved record', {
      my $alice = User.create({fname => 'alice'});
      my $built = $alice.extended-articles.build({title => 'draft', body => 'd'});
      expect($built.id).to.be-falsy;
    }

    it 'sets the foreign key', {
      my $alice = User.create({fname => 'alice'});
      my $built = $alice.extended-articles.build({title => 'draft', body => 'd'});
      expect($built.attrs<author_id>).to.eq($alice.id);
    }
  }

  context 'create', {
    it 'returns a saved record', {
      my $alice = User.create({fname => 'alice'});
      my $created = $alice.extended-articles.create({title => 'live', body => 'b', score => 10});
      expect($created.id).to.be-greater-than(0);
    }

    it 'sets the foreign key', {
      my $alice = User.create({fname => 'alice'});
      my $created = $alice.extended-articles.create({title => 'live', body => 'b', score => 10});
      expect($created.attrs<author_id>).to.eq($alice.id);
    }
  }

  context 'create-or-die', {
    it 'returns a saved record', {
      my $alice = User.create({fname => 'alice'});
      my $forced = $alice.extended-articles.create-or-die({title => 'forced', body => 'b'});
      expect($forced.id).to.be-greater-than(0);
    }

    it 'sets the foreign key', {
      my $alice = User.create({fname => 'alice'});
      my $forced = $alice.extended-articles.create-or-die({title => 'forced', body => 'b'});
      expect($forced.attrs<author_id>).to.eq($alice.id);
    }
  }

  context 'push / append', {
    it 'orphan has no author before push', {
      User.create({fname => 'alice'});
      my $orphan = Article.create({title => 'orphan', body => 'o'});
      expect($orphan.attrs<author_id>).to.eq(0);
    }

    it 'push sets the foreign key', {
      my $alice = User.create({fname => 'alice'});
      my $orphan = Article.create({title => 'orphan', body => 'o'});
      $alice.extended-articles.push($orphan);
      my $reloaded = Article.find($orphan.id);
      expect($reloaded.attrs<author_id>).to.eq($alice.id);
    }

    it 'pushed records are visible on reload', {
      my $alice = User.create({fname => 'alice'});
      my $orphan = Article.create({title => 'orphan', body => 'o'});
      $alice.extended-articles.push($orphan);
      my $b = Article.create({title => 'b', body => 'b'});
      my $c = Article.create({title => 'c', body => 'c'});
      $alice.extended-articles.append($b);
      $alice.extended-articles.push($c);

      expect($alice.extended-articles.elems).to.eq(3);
    }
  }

  context 'delete / destroy / clear', {
    it 'starts with three children', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'p1', body => 'b'});
      $alice.extended-articles.create({title => 'p2', body => 'b'});
      $alice.extended-articles.create({title => 'p3', body => 'b'});

      expect($alice.extended-articles.elems).to.eq(3);
    }

    it 'delete nullifies FK but keeps row', {
      my $alice = User.create({fname => 'alice'});
      my $p1 = $alice.extended-articles.create({title => 'p1', body => 'b'});
      $alice.extended-articles.delete($p1);
      my $nullified = Article.find($p1.id);

      expect($nullified.attrs<author_id>).to.be-falsy;
    }

    it 'collection drops the deleted record', {
      my $alice = User.create({fname => 'alice'});
      my $p1 = $alice.extended-articles.create({title => 'p1', body => 'b'});
      $alice.extended-articles.create({title => 'p2', body => 'b'});
      $alice.extended-articles.delete($p1);

      expect($alice.extended-articles.elems).to.eq(1);
    }

    it 'destroy actually removes the row', {
      my $alice = User.create({fname => 'alice'});
      my $p2 = $alice.extended-articles.create({title => 'p2', body => 'b'});
      $alice.extended-articles.destroy($p2);

      expect(Article.where({id => $p2.id}).count).to.eq(0);
    }

    it 'clear empties the collection', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'p3', body => 'b'});
      $alice.extended-articles.clear;

      expect($alice.extended-articles.elems).to.eq(0);
    }

    it 'clear leaves the row in place', {
      my $alice = User.create({fname => 'alice'});
      my $p3 = $alice.extended-articles.create({title => 'p3', body => 'b'});
      $alice.extended-articles.clear;

      expect(Article.where({id => $p3.id}).first.defined).to.be-truthy;
    }
  }

  context 'is-empty / size / count / length', {
    it 'is-empty true on fresh association', {
      my $alice = User.create({fname => 'alice'});
      expect($alice.extended-articles.is-empty).to.be-truthy;
    }

    it 'size is 0 on fresh association', {
      my $alice = User.create({fname => 'alice'});
      expect($alice.extended-articles.size).to.eq(0);
    }

    it 'count is 0 on fresh association', {
      my $alice = User.create({fname => 'alice'});
      expect($alice.extended-articles.count).to.eq(0);
    }

    it 'length is 0 on fresh association', {
      my $alice = User.create({fname => 'alice'});
      expect($alice.extended-articles.length).to.eq(0);
    }

    it 'is-empty false after creates', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'a', body => 'b'});
      $alice.extended-articles.create({title => 'c', body => 'd'});
      expect($alice.extended-articles.is-empty).to.be-falsy;
    }

    it 'size matches', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'a', body => 'b'});
      $alice.extended-articles.create({title => 'c', body => 'd'});
      expect($alice.extended-articles.size).to.eq(2);
    }

    it 'count matches', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'a', body => 'b'});
      $alice.extended-articles.create({title => 'c', body => 'd'});
      expect($alice.extended-articles.count).to.eq(2);
    }

    it 'length matches', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'a', body => 'b'});
      $alice.extended-articles.create({title => 'c', body => 'd'});
      expect($alice.extended-articles.length).to.eq(2);
    }
  }

  context 'exists / find', {
    it 'exists() returns True with members', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'a', body => 'b'});
      expect($alice.extended-articles.exists).to.be-truthy;
    }

    it 'exists(id) finds a member', {
      my $alice = User.create({fname => 'alice'});
      my $p1 = $alice.extended-articles.create({title => 'a', body => 'b'});
      expect($alice.extended-articles.exists($p1.id)).to.be-truthy;
    }

    it 'exists(unknown-id) is False', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'a', body => 'b'});
      expect($alice.extended-articles.exists(9999)).to.be-falsy;
    }

    it 'exists(hash) matches by attrs', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'a', body => 'b'});
      expect($alice.extended-articles.exists({title => 'a'})).to.be-truthy;
    }

    it 'exists(hash) misses unknown attrs', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'a', body => 'b'});
      expect($alice.extended-articles.exists({title => 'missing'})).to.be-falsy;
    }

    it 'find(id) returns the matching record', {
      my $alice = User.create({fname => 'alice'});
      my $p2 = $alice.extended-articles.create({title => 'c', body => 'd'});
      expect($alice.extended-articles.find($p2.id).attrs<title>).to.eq('c');
    }

    it 'find(unknown-id) raises', {
      my $alice = User.create({fname => 'alice'});
      expect({ $alice.extended-articles.find(9999) }).to.raise-error;
    }
  }

  context 'replace', {
    it 'leaves only the new set', {
      my $alice = User.create({fname => 'alice'});
      my $keep   = $alice.extended-articles.create({title => 'keep', body => 'b'});
      $alice.extended-articles.create({title => 'd1', body => 'b'});
      $alice.extended-articles.create({title => 'd2', body => 'b'});
      my $newone = Article.create({title => 'new', body => 'b'});
      $alice.extended-articles.replace([$keep, $newone]);

      expect($alice.extended-articles.list.elems).to.eq(2);
    }

    it 'contains exactly the requested rows', {
      my $alice = User.create({fname => 'alice'});
      my $keep   = $alice.extended-articles.create({title => 'keep', body => 'b'});
      $alice.extended-articles.create({title => 'd1', body => 'b'});
      my $newone = Article.create({title => 'new', body => 'b'});
      $alice.extended-articles.replace([$keep, $newone]);

      expect($alice.extended-articles.list.sort({ .attrs<title> }).map({ .attrs<title> }).sort.join(',')).to.eq('keep,new');
    }

    it 'nullifies first dropped row', {
      my $alice = User.create({fname => 'alice'});
      my $keep   = $alice.extended-articles.create({title => 'keep', body => 'b'});
      my $drop1  = $alice.extended-articles.create({title => 'd1', body => 'b'});
      $alice.extended-articles.create({title => 'd2', body => 'b'});
      my $newone = Article.create({title => 'new', body => 'b'});
      $alice.extended-articles.replace([$keep, $newone]);

      expect(Article.find($drop1.id).attrs<author_id>).to.be-falsy;
    }

    it 'nullifies other dropped rows', {
      my $alice = User.create({fname => 'alice'});
      my $keep   = $alice.extended-articles.create({title => 'keep', body => 'b'});
      $alice.extended-articles.create({title => 'd1', body => 'b'});
      my $drop2  = $alice.extended-articles.create({title => 'd2', body => 'b'});
      my $newone = Article.create({title => 'new', body => 'b'});
      $alice.extended-articles.replace([$keep, $newone]);

      expect(Article.find($drop2.id).attrs<author_id>).to.be-falsy;
    }
  }

  context 'association extension role', {
    it 'high-score returns matches', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'low',  body => '', score => 1});
      $alice.extended-articles.create({title => 'mid',  body => '', score => 5});
      $alice.extended-articles.create({title => 'high', body => '', score => 9});

      expect($alice.extended-articles.high-score(5).elems).to.eq(2);
    }

    it 'high-score picks the right rows', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'low',  body => '', score => 1});
      $alice.extended-articles.create({title => 'mid',  body => '', score => 5});
      $alice.extended-articles.create({title => 'high', body => '', score => 9});

      expect($alice.extended-articles.high-score(5).map({ .attrs<title> }).sort.join(',')).to.eq('high,mid');
    }

    it 'by-title sorts via the underlying records', {
      my $alice = User.create({fname => 'alice'});
      $alice.extended-articles.create({title => 'low',  body => '', score => 1});
      $alice.extended-articles.create({title => 'mid',  body => '', score => 5});
      $alice.extended-articles.create({title => 'high', body => '', score => 9});

      expect($alice.extended-articles.by-title.map({ .attrs<title> }).join(',')).to.eq('high,low,mid');
    }
  }

  context 'polymorphic has-many proxy', {
    it 'sets <as>_id', {
      my $alice = User.create({fname => 'alice'});
      my $c1 = $alice.comments.create({body => 'first'});
      expect($c1.attrs<commentable_id>).to.eq($alice.id);
    }

    it 'sets <as>_type', {
      my $alice = User.create({fname => 'alice'});
      my $c1 = $alice.comments.create({body => 'first'});
      expect($c1.attrs<commentable_type>).to.eq('User');
    }

    it 'collection size', {
      my $alice = User.create({fname => 'alice'});
      $alice.comments.create({body => 'first'});
      $alice.comments.create({body => 'second'});
      expect($alice.comments.size).to.eq(2);
    }

    it 'delete nullifies <as>_id', {
      my $alice = User.create({fname => 'alice'});
      my $c1 = $alice.comments.create({body => 'first'});
      $alice.comments.create({body => 'second'});
      $alice.comments.delete($c1);
      my $reloaded = Comment.find($c1.id);

      expect($reloaded.attrs<commentable_id>).to.be-falsy;
    }
  }
}
