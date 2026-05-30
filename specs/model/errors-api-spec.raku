use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Errors::Errors;
use ORM::ActiveRecord::Schema::Field;
use Model::ErrorsApi;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'errors API', {
  before-each {
    Banquet.destroy-all;
  }

  after-each {
    Banquet.destroy-all;
  }

  context 'add with a type symbol', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');
    }

    it 'populates errors', {
      expect($e.errors.is-any).to.be-truthy;
    }

    it 'reports size 1', {
      expect($e.errors.size).to.eq(1);
    }

    it 'stores the type', {
      expect($e.errors[0].type).to.eq('blank');
    }

    it 'chooses the default template for a known type', {
      expect($e.errors[0].message).to.eq('must be present');
    }
  }

  context 'add with an explicit :message override', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'taken', message => 'is already taken by friend');
    }

    it 'keeps the type', {
      expect($e.errors[0].type).to.eq('taken');
    }

    it 'uses the explicit message', {
      expect($e.errors[0].message).to.eq('is already taken by friend');
    }
  }

  context 'add with a bare-string message', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'must be cool');
    }

    it 'defaults the type to invalid for a whitespace-bearing arg', {
      expect($e.errors[0].type).to.eq('invalid');
    }

    it 'stores the message verbatim', {
      expect($e.errors[0].message).to.eq('must be cool');
    }
  }

  context 'add with option interpolation', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('score', 'greater-than', count => 0);
    }

    it 'interpolates {count}', {
      expect($e.errors[0].message).to.eq('must be greater than 0');
    }

    it 'preserves the option on the error', {
      expect($e.errors[0].options<count>).to.eq(0);
    }
  }

  context 'import accepts a prebuilt Error', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      my $field = Field.new(:name<name>, :type<attribute>);
      $e.errors.import(Error.new(:$field, :message<imported>, :type<custom>));
    }

    it 'stores the imported message', {
      expect($e.errors[0].message).to.eq('imported');
    }

    it 'preserves the imported type', {
      expect($e.errors[0].type).to.eq('custom');
    }
  }

  context 'delete by attribute', {
    my $e;
    my @removed;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name',  'blank');
      $e.errors.add('score', 'greater-than', count => 0);

      @removed = $e.errors.delete('name');
    }

    it 'returns the removed errors', {
      expect(@removed.elems).to.eq(1);
    }

    it 'keeps the other attribute', {
      expect($e.errors.size).to.eq(1);
    }

    it 'leaves the surviving error attribute', {
      expect($e.errors[0].attribute).to.eq('score');
    }
  }

  context 'delete by attribute + type', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');
      $e.errors.add('name', 'taken');

      $e.errors.delete('name', 'blank');
    }

    it 'removes only the matching type', {
      expect($e.errors.size).to.eq(1);
    }

    it 'keeps the non-matching error', {
      expect($e.errors[0].type).to.eq('taken');
    }
  }

  context 'clear', {
    it 'empties all errors', {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');
      $e.errors.add('score', 'greater-than', count => 0);

      $e.errors.clear;

      expect($e.errors.is-empty).to.be-truthy;
    }
  }

  context 'full-messages prepends the attribute', {
    my $e;
    my @msgs;

    before-each {
      $e = Banquet.build({name => '', score => 5});
      $e.is-invalid;
      @msgs = $e.errors.full-messages;
    }

    it 'has one error from presence', {
      expect(@msgs.elems).to.eq(1);
    }

    it 'prefixes the message with the attribute', {
      expect(@msgs[0]).to.eq('name must be present');
    }
  }

  context 'base errors are not prefixed', {
    it 'leaves the base message untouched', {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('base', 'something broke');

      expect($e.errors.full-messages[0]).to.eq('something broke');
    }
  }

  context 'full-messages-for filters by attribute', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name',  'blank');
      $e.errors.add('score', 'greater-than', count => 0);
    }

    it 'returns only matching errors', {
      expect($e.errors.full-messages-for('score').elems).to.eq(1);
    }

    it 'returns the attribute-scoped full message', {
      expect($e.errors.full-messages-for('score')[0]).to.eq('score must be greater than 0');
    }
  }

  context 'errors.details', {
    my %d;

    before-each {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');
      $e.errors.add('score', 'greater-than', count => 0);

      %d = $e.errors.details;
    }

    it 'captures type as error key for name', {
      expect(%d<name>[0]<error>).to.eq('blank');
    }

    it 'captures type as error key for score', {
      expect(%d<score>[0]<error>).to.eq('greater-than');
    }

    it 'surfaces options inside details', {
      expect(%d<score>[0]<count>).to.eq(0);
    }
  }

  context 'errors.where filters by attribute and type', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');
      $e.errors.add('name', 'taken');
      $e.errors.add('score', 'greater-than', count => 0);
    }

    it 'returns all errors for an attribute', {
      expect($e.errors.where(:attribute<name>).elems).to.eq(2);
    }

    it 'returns all errors for a type', {
      expect($e.errors.where(:type<taken>).elems).to.eq(1);
    }

    it 'narrows correctly when both are given', {
      expect($e.errors.where(:attribute<name>, :type<blank>).elems).to.eq(1);
    }
  }

  context 'is-of-kind', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');
    }

    it 'matches the recorded kind', {
      expect($e.errors.is-of-kind('name', 'blank')).to.be-truthy;
    }

    it 'returns False for an unmatched kind', {
      expect($e.errors.is-of-kind('name', 'taken')).to.be-falsy;
    }

    it 'returns False for an attribute mismatch', {
      expect($e.errors.is-of-kind('score', 'blank')).to.be-falsy;
    }
  }

  context 'is-added with options', {
    my $e;

    before-each {
      $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('score', 'greater-than', count => 0);
    }

    it 'matches with the same options', {
      expect($e.errors.is-added('score', 'greater-than', count => 0)).to.be-truthy;
    }

    it 'returns False on option mismatch', {
      expect($e.errors.is-added('score', 'greater-than', count => 1)).to.be-falsy;
    }

    it 'returns False on type mismatch', {
      expect($e.errors.is-added('score', 'less-than')).to.be-falsy;
    }
  }

  context 'size / count / is-any / is-empty', {
    it 'is empty by default', {
      my $e = Banquet.build({name => 'A', score => 5});

      expect($e.errors.is-empty).to.be-truthy;
    }

    it 'is-any is False when empty', {
      my $e = Banquet.build({name => 'A', score => 5});

      expect($e.errors.is-any).to.be-falsy;
    }

    it 'size reflects one error', {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');

      expect($e.errors.size).to.eq(1);
    }

    it 'count is an alias of size', {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');

      expect($e.errors.count).to.eq(1);
    }

    it 'is-any is True after add', {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');

      expect($e.errors.is-any).to.be-truthy;
    }

    it 'is-empty is False after add', {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name', 'blank');

      expect($e.errors.is-empty).to.be-falsy;
    }
  }

  context 'group-by-attribute', {
    my %g;

    before-each {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('name',  'blank');
      $e.errors.add('name',  'taken');
      $e.errors.add('score', 'greater-than', count => 0);

      %g = $e.errors.group-by-attribute;
    }

    it 'groups two errors under name', {
      expect(%g<name>.elems).to.eq(2);
    }

    it 'groups one error under score', {
      expect(%g<score>.elems).to.eq(1);
    }

    it 'returns Error objects in the groups', {
      expect(%g<name>[0]).to.be-a(Error);
    }
  }

  context 'objects iteration', {
    my @objs;

    before-each {
      my $e = Banquet.build({name => 'A', score => 5});
      $e.errors.add('score', 'greater-than', count => 0);

      @objs = $e.errors.objects;
    }

    it 'yields the stored errors', {
      expect(@objs.elems).to.eq(1);
    }

    it 'exposes .message', {
      expect(@objs[0].message).to.eq('must be greater than 0');
    }

    it 'exposes .type', {
      expect(@objs[0].type).to.eq('greater-than');
    }

    it 'exposes .options', {
      expect(@objs[0].options<count>).to.eq(0);
    }
  }

  context 'merge between records', {
    my $a;

    before-each {
      $a = Banquet.build({name => 'A', score => 5});
      my $b = Banquet.build({name => 'B', score => 5});

      $a.errors.add('name',  'blank');
      $b.errors.add('score', 'greater-than', count => 0);

      $a.errors.merge($b.errors);
    }

    it 'appends the other errors', {
      expect($a.errors.size).to.eq(2);
    }

    it 'retains the merged error type', {
      expect($a.errors.is-of-kind('score', 'greater-than')).to.be-truthy;
    }
  }

  context 'FALLBACK access by attribute name', {
    it 'still works for backward compatibility', {
      my $e = Banquet.build({name => '', score => 5});
      $e.is-invalid;

      expect($e.errors.name[0]).to.eq('must be present');
    }
  }
}
