use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Environment;

# DB.shared caches one connection per name in a process-wide hash. A web server
# serves requests on a thread pool, so many threads call DB.shared at once (a
# page full of images fires a burst of concurrent /imgs/:id requests). Before
# the shared hash was locked, the concurrent check-then-build corrupted it and
# MoarVM aborted with "MVM_str_hash_lvalue_fetch_nocheck called concurrently on
# the same hash". This drives that exact path: reaching the end without the VM
# aborting is the regression signal, plus the cache must still behave as a
# singleton under contention.

%*ENV<DISABLE-SQL-LOG> = True;

describe 'DB.shared under concurrent access', {
  let(:name, { default-connection() });

  let(:contention, {
    my $threads = 32;
    my $rounds  = 40;
    my @exceptions;
    my @distinct-per-round;

    for ^$rounds {
      # Force a rebuild so every round races the initial //= build, the slot
      # that actually corrupted the hash, not just reads of a warm entry.
      DB.set-shared(DB, name => name);

      my @results = await (^$threads).map: {
        start {
          CATCH { default { @exceptions.push($_); Nil } }
          DB.shared(name => name);
        }
      }

      @distinct-per-round.push: @results.grep(*.defined).map({ .WHICH }).unique.elems;
    }

    { exceptions => @exceptions, distinct-per-round => @distinct-per-round }
  });

  it 'raises no exception while many threads resolve the shared connection', {
    expect(contention<exceptions>.elems).to.eq(0);
  }

  it 'resolves to a single shared connection every round under contention', {
    expect(contention<distinct-per-round>.all == 1).to.be-truthy;
  }

  it 'leaves the shared connection usable after the contention run', {
    expect(DB.shared(name => name).defined).to.be-truthy;
  }
}
