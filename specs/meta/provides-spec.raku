use lib 'lib';
use BDD::Behave;
use JSON::Fast;

sub find-rakumod(IO::Path $dir) {
  gather for $dir.dir {
    when .d                      { .take for find-rakumod($_) }
    when .extension eq 'rakumod' { .take }
  }
}

my %meta            = from-json('META6.json'.IO.slurp);
my %provided-paths  = %meta<provides>.values.Set;
my @rakumod-files   = find-rakumod('lib'.IO).map(*.relative).sort;

describe 'META6.json provides', {
  context 'every lib/**/*.rakumod is listed', {
    for @rakumod-files -> $rel {
      it $rel, {
        expect(%provided-paths{$rel}:exists).to.be-truthy;
      }
    }
  }
}
