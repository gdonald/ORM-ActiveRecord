use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

my &group = $has-db ?? &describe !! &xdescribe;

group 'prohibit-shard-swapping', {
  it 'is False by default', {
    expect(DB.shared.is-shard-swapping-prohibited).to.be-falsy;
  }

  it 'is True inside the block', {
    my $inside;
    DB.shared.prohibit-shard-swapping({ $inside = DB.shared.is-shard-swapping-prohibited });
    expect($inside).to.be-truthy;
  }

  it 'clears after the block', {
    DB.shared.prohibit-shard-swapping(sub {});
    expect(DB.shared.is-shard-swapping-prohibited).to.be-falsy;
  }

  context 'nesting', {
    it 'flag survives the inner block', {
      my $inner;
      DB.shared.prohibit-shard-swapping({
        DB.shared.prohibit-shard-swapping({
          $inner = DB.shared.is-shard-swapping-prohibited;
        });
      });
      expect($inner).to.be-truthy;
    }

    it 'outer block still flagged after inner exit', {
      my $outer-after-inner;
      DB.shared.prohibit-shard-swapping({
        DB.shared.prohibit-shard-swapping(sub {});
        $outer-after-inner = DB.shared.is-shard-swapping-prohibited;
      });
      expect($outer-after-inner).to.be-truthy;
    }

    it 'both blocks clear at the end', {
      DB.shared.prohibit-shard-swapping({
        DB.shared.prohibit-shard-swapping(sub {});
      });
      expect(DB.shared.is-shard-swapping-prohibited).to.be-falsy;
    }
  }

  it 'clears after an exception', {
    try { DB.shared.prohibit-shard-swapping({ die 'boom' }) };
    expect(DB.shared.is-shard-swapping-prohibited).to.be-falsy;
  }
}

group 'prohibit-replica-swapping', {
  it 'is False by default', {
    expect(DB.shared.is-replica-swapping-prohibited).to.be-falsy;
  }

  it 'is True inside the block', {
    my $inside;
    DB.shared.prohibit-replica-swapping({ $inside = DB.shared.is-replica-swapping-prohibited });
    expect($inside).to.be-truthy;
  }

  it 'clears after the block', {
    DB.shared.prohibit-replica-swapping(sub {});
    expect(DB.shared.is-replica-swapping-prohibited).to.be-falsy;
  }

  it 'flag survives the inner block when nested', {
    my $inner;
    DB.shared.prohibit-replica-swapping({
      DB.shared.prohibit-replica-swapping({
        $inner = DB.shared.is-replica-swapping-prohibited;
      });
    });
    expect($inner).to.be-truthy;
  }

  it 'nesting clears completely at the end', {
    DB.shared.prohibit-replica-swapping({
      DB.shared.prohibit-replica-swapping(sub {});
    });
    expect(DB.shared.is-replica-swapping-prohibited).to.be-falsy;
  }
}

group 'flag independence', {
  it 'replica flag is not raised by a shard block', {
    my $replica-inside;
    DB.shared.prohibit-shard-swapping({
      $replica-inside = DB.shared.is-replica-swapping-prohibited;
    });
    expect($replica-inside).to.be-falsy;
  }

  it 'shard flag is not raised by a replica block', {
    my $shard-inside;
    DB.shared.prohibit-replica-swapping({
      $shard-inside = DB.shared.is-shard-swapping-prohibited;
    });
    expect($shard-inside).to.be-falsy;
  }
}
