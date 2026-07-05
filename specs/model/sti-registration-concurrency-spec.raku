use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

# The STI registry (%sti-registered / %sti-by-name) is process-global and fills
# in lazily: the first read or instantiation of a subclass registers it. A web
# server drives that path from many request threads at once. Before the registry
# was locked, the concurrent register-then-read raced the same hash and MoarVM
# aborted with a concurrent-hash error. This drives many threads through
# registration and the descendant reads together: reaching the end without the
# VM aborting is the regression signal, and every thread must still resolve each
# subclass to the right class.

%*ENV<DISABLE-SQL-LOG> = True;

class Terrain is Model { method table-name { 'terrains' } }
class Desert  is Terrain { }
class Forest  is Terrain { }
class Tundra  is Terrain { }

GLOBAL::<Terrain> := Terrain;
GLOBAL::<Desert>  := Desert;
GLOBAL::<Forest>  := Forest;
GLOBAL::<Tundra>  := Tundra;

describe 'STI registration under concurrent access', {
  let(:outcomes, {
    my @names   = <Desert Forest Tundra>;
    my $threads = 48;

    await (^$threads).map: -> $i {
      start {
        my $type-name = @names[$i % @names.elems];
        my $error     = Str;
        my $resolved  = Str;

        {
          CATCH { default { $error = .Str } }
          $resolved = Terrain.sti-class-for($type-name).^name;
          Terrain.sti-descendants;
        }

        %( :$type-name, :$resolved, :$error );
      }
    }
  });

  it 'raises no exception while many threads register and read the STI hierarchy', {
    expect(outcomes.grep({ .<error>.defined }).elems).to.eq(0);
  }

  it 'resolves every subclass to its own class from every thread', {
    expect(outcomes.grep({ !.<resolved>.ends-with(.<type-name>) }).elems).to.eq(0);
  }

  it 'registers each subclass exactly once across the whole run', {
    outcomes;
    expect(Terrain.sti-descendants.map({ .^name.split('::').tail }).sort.List).to.eq(<Desert Forest Tundra>.List);
  }
}
