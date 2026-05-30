use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Article;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'has-many with query-constraints', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'user A as coauthor 7', {
    it 'returns rows matching both columns', {
      my $user-a = User.create({fname => 'A'});
      my $user-b = User.create({fname => 'B'});
      Article.create({title => 'a7-1', author_id => $user-a.id, coauthor_id => 7});
      Article.create({title => 'a7-2', author_id => $user-a.id, coauthor_id => 7});
      Article.create({title => 'a8-1', author_id => $user-a.id, coauthor_id => 8});
      Article.create({title => 'b7-1', author_id => $user-b.id, coauthor_id => 7});

      my $a-as-co7 = User.find($user-a.id);
      $a-as-co7.attrs<coauthor_id> = 7;

      expect($a-as-co7.coauthored-docs.elems).to.eq(2);
    }

    it 'returns the right two titles', {
      my $user-a = User.create({fname => 'A'});
      Article.create({title => 'a7-1', author_id => $user-a.id, coauthor_id => 7});
      Article.create({title => 'a7-2', author_id => $user-a.id, coauthor_id => 7});
      Article.create({title => 'a8-1', author_id => $user-a.id, coauthor_id => 8});

      my $a-as-co7 = User.find($user-a.id);
      $a-as-co7.attrs<coauthor_id> = 7;
      my @docs = $a-as-co7.coauthored-docs.sort({ $_.attrs<title> });

      expect(@docs.map({ $_.attrs<title> }).join(',')).to.eq('a7-1,a7-2');
    }
  }

  it 'picks up a different coauthor_id', {
    my $user-a = User.create({fname => 'A'});
    Article.create({title => 'a7-1', author_id => $user-a.id, coauthor_id => 7});
    Article.create({title => 'a8-1', author_id => $user-a.id, coauthor_id => 8});

    my $a-as-co8 = User.find($user-a.id);
    $a-as-co8.attrs<coauthor_id> = 8;

    expect($a-as-co8.coauthored-docs.elems).to.eq(1);
  }

  it 'scopes by author too', {
    my $user-a = User.create({fname => 'A'});
    my $user-b = User.create({fname => 'B'});
    Article.create({title => 'a7-1', author_id => $user-a.id, coauthor_id => 7});
    Article.create({title => 'b7-1', author_id => $user-b.id, coauthor_id => 7});

    my $b-as-co7 = User.find($user-b.id);
    $b-as-co7.attrs<coauthor_id> = 7;

    expect($b-as-co7.coauthored-docs.elems).to.eq(1);
  }

  it 'returns no matching docs for (B, 8)', {
    my $user-b = User.create({fname => 'B'});
    Article.create({title => 'b7-1', author_id => $user-b.id, coauthor_id => 7});

    my $b-as-co8 = User.find($user-b.id);
    $b-as-co8.attrs<coauthor_id> = 8;

    expect($b-as-co8.coauthored-docs.elems).to.eq(0);
  }
}
