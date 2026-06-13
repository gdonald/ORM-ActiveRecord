use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use Models::Workshop;
use Models::Tool;
use Models::Signboard;

%*ENV<DISABLE-SQL-LOG> = True;

# Itemise each record hash so the array of nested records is not flattened
# into a single list of pairs when the spec file is evaluated.
sub rec(*%h) { $(%h) }

sub tool-count(Int $wid) { Tool.where({workshop_id => $wid}).all.elems }
sub sign-count(Int $wid) { Signboard.where({workshop_id => $wid}).all.elems }

describe 'nested attributes', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  describe 'has-many', {
    it 'builds one child per entry in the array', {
      my $shop = Workshop.create({
        name => 'Main',
        tools-attributes => [ rec(name => 'hammer', level => 1), rec(name => 'saw', level => 2) ],
      });
      expect(tool-count($shop.id)).to.eq(2);
    }

    it 'carries the parent foreign key onto each child', {
      my $shop = Workshop.create({
        name => 'Main',
        tools-attributes => [ rec(name => 'hammer', level => 1) ],
      });
      expect(Tool.where({workshop_id => $shop.id}).first.attrs<workshop_id>).to.eq($shop.id);
    }

    it 'skips entries the reject-if predicate rejects', {
      my $shop = Workshop.create({
        name => 'Rejects',
        tools-attributes => [ rec(name => 'plane', level => 1), rec(name => '', level => 9) ],
      });
      expect(tool-count($shop.id)).to.eq(1);
    }

    it 'raises when the entry count exceeds the limit', {
      expect({
        Workshop.create({
          name => 'TooMany',
          tools-attributes => (^6).map({ rec(name => "t$_", level => $_) }).list,
        });
      }).to.throw;
    }

    context 'updating an existing child by id', {
      it 'updates the named child in place', {
        my $shop = Workshop.create({
          name => 'Edit',
          tools-attributes => [ rec(name => 'hammer', level => 1) ],
        });
        my $tool = Tool.where({workshop_id => $shop.id}).first;
        $shop.update({ tools-attributes => [ rec(id => $tool.attrs<id>, name => 'mallet', level => 7) ] });

        expect(Tool.find($tool.attrs<id>).attrs<name>).to.eq('mallet');
      }

      it 'does not create a duplicate', {
        my $shop = Workshop.create({
          name => 'Edit',
          tools-attributes => [ rec(name => 'hammer', level => 1) ],
        });
        my $tool = Tool.where({workshop_id => $shop.id}).first;
        $shop.update({ tools-attributes => [ rec(id => $tool.attrs<id>, name => 'mallet') ] });

        expect(tool-count($shop.id)).to.eq(1);
      }
    }

    context 'destroying a child', {
      it 'removes the child when allow-destroy is enabled', {
        my $shop = Workshop.create({
          name => 'Drop',
          tools-attributes => [ rec(name => 'hammer'), rec(name => 'saw') ],
        });
        my $tool = Tool.where({workshop_id => $shop.id}).first;
        $shop.update({ tools-attributes => [ rec(id => $tool.attrs<id>, _destroy => 1) ] });

        expect(tool-count($shop.id)).to.eq(1);
      }
    }
  }

  describe 'has-one', {
    it 'builds the single child from a nested hash', {
      my $shop = Workshop.create({
        name => 'Signed',
        signboard-attributes => { slogan => 'open' },
      });
      expect(Workshop.find($shop.id).signboard.attrs<slogan>).to.eq('open');
    }

    context 'update-only', {
      it 'updates the existing child instead of adding another', {
        my $shop = Workshop.create({
          name => 'Signed',
          signboard-attributes => { slogan => 'open' },
        });
        $shop.update({ signboard-attributes => { slogan => 'closed' } });

        expect(sign-count($shop.id)).to.eq(1);
      }

      it 'applies the new attributes to the existing child', {
        my $shop = Workshop.create({
          name => 'Signed',
          signboard-attributes => { slogan => 'open' },
        });
        $shop.update({ signboard-attributes => { slogan => 'closed' } });

        expect(Workshop.find($shop.id).signboard.attrs<slogan>).to.eq('closed');
      }
    }
  }

  describe 'validation', {
    it 'blocks the parent save when a nested child is invalid', {
      my $shop = Workshop.create({
        name => 'Bad',
        signboard-attributes => { slogan => '' },
      });
      expect($shop.id).to.eq(0);
    }

    it 'records the invalid association on the parent', {
      my $shop = Workshop.create({
        name => 'Bad',
        signboard-attributes => { slogan => '' },
      });
      expect($shop.errors.errors.elems).to.be-greater-than(0);
    }
  }
}
