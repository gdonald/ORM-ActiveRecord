use lib 'lib';
use BDD::Behave;
use DBIish;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class ReflAuthor is Model {
  method table-name { 'refl_authors' }
  submethod BUILD {
    self.has-many: refl_books => class-name => 'ReflBook';
    self.enum: 'role', { admin => 0, user => 1 };
  }
}

class ReflBook is Model {
  method table-name { 'refl_books' }
  submethod BUILD {
    self.belongs-to: reflauthor => class-name => 'ReflAuthor';
    self.belongs-to: cover      => :polymorphic;
  }
}

GLOBAL::<ReflAuthor> := ReflAuthor;
GLOBAL::<ReflBook>   := ReflBook;

%*ENV<BEHAVE_WORKER_INDEX>:delete;
%*ENV<BEHAVE_WORKER_COUNT>:delete;
%*ENV<DATABASE_URL> = "sqlite:" ~ $*TMPDIR.add("reflection-spec-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
DB.set-shared(Nil);

my $adapter = DB.shared.adapter;
$adapter.ddl-create-table('refl_authors', [ name => { :string, limit => 32 }, role => { :integer } ]);
$adapter.ddl-add-timestamps('refl_authors');
$adapter.ddl-create-table('refl_books', [
  title      => { :string, limit => 64 },
  reflauthor => { :reference },
  cover      => { :reference, :polymorphic },
]);

describe 'association reflection', {
  it 'lists the declared associations', {
    expect(ReflAuthor.association-names).to.eq(('refl_books',));
  }

  context 'a has-many', {
    let(:reflection, { ReflAuthor.reflect-on-association('refl_books') });

    it 'reports the macro and collection kind', {
      aggregate-failures {
        expect(reflection.macro).to.eq('has-many');
        expect(reflection.is-collection).to.be-truthy;
        expect(reflection.is-singular).to.be-falsy;
      }
    }

    it 'resolves the target class and foreign key', {
      aggregate-failures {
        expect(reflection.klass === ReflBook).to.be-truthy;
        expect(reflection.foreign-key).to.eq('reflauthor_id');
      }
    }
  }

  context 'a polymorphic belongs-to', {
    let(:reflection, { ReflBook.reflect-on-association('cover') });

    it 'reflects as polymorphic with an id foreign key', {
      aggregate-failures {
        expect(reflection.polymorphic).to.be-truthy;
        expect(reflection.foreign-key).to.eq('cover_id');
        expect(reflection.is-singular).to.be-truthy;
      }
    }
  }
}

describe 'schema reflection', {
  it 'lists column names and their types', {
    aggregate-failures {
      expect(ReflAuthor.column-names.grep({ $_ eq 'role' }).elems).to.be-truthy;
      expect(ReflAuthor.column-type('role')).to.eq('integer');
      expect(ReflAuthor.column('name')<null>).to.be-truthy;
    }
  }

  it 'reports the primary key and its type', {
    aggregate-failures {
      expect(ReflAuthor.primary-keys).to.eq(('id',));
      expect(ReflAuthor.primary-key-type).to.eq('integer');
    }
  }

  it 'exposes the enum name to value map', {
    expect(ReflAuthor.enums<role><admin>).to.eq(0);
  }
}

describe 'build-stubbed', {
  let(:stub, { ReflAuthor.build-stubbed({ name => 'Ada' }) });

  it 'reports the stub as persisted with timestamps', {
    aggregate-failures {
      expect(stub.is-persisted).to.be-truthy;
      expect(stub.attrs<created_at>.defined).to.be-truthy;
    }
  }

  it 'raises on save', {
    expect({ stub.save }).to.raise-error(X::ReadOnlyRecord);
  }

  it 'raises on reload', {
    expect({ stub.reload }).to.raise-error(X::StubbedRecord);
  }
}
