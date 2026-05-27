use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub adapter-kind(--> Str) {
  given $adapter.^name {
    when /Pg/     { 'pg' }
    when /MySql/  { 'mysql' }
    when /Sqlite/ { 'sqlite' }
    default       { 'unknown' }
  }
}

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub column-names($table) {
  $adapter.get-fields(table => $table).map({ $_[0] }).list;
}

sub index-exists($name) {
  my $rows = do given adapter-kind() {
    when 'pg'     { $adapter.exec("SELECT 1 FROM pg_indexes WHERE indexname = '$name'") }
    when 'mysql'  { $adapter.exec("SELECT 1 FROM information_schema.statistics WHERE table_schema = DATABASE() AND index_name = '$name'") }
    when 'sqlite' { $adapter.exec("SELECT 1 FROM sqlite_master WHERE type='index' AND name='$name'") }
  };
  ?$rows.elems;
}

my @test-tables = <_ref_posts _ref_users>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class RefCreateUsers is Migration {
  method change {
    self.create-table: '_ref_users', [ name => { :string, limit => 32 } ];
  }
}

class RefCreatePosts is Migration {
  method change {
    self.create-table: '_ref_posts', [ title => { :string, limit => 32 } ];
  }
}

class AddUserRef is Migration {
  method change {
    self.add-reference: '_ref_posts', 'user';
  }
}

class AddOwnerBelongsTo is Migration {
  method change {
    self.add-belongs-to: '_ref_posts', 'owner';
  }
}

class AddCommentablePoly is Migration {
  method change {
    self.add-reference: '_ref_posts', 'commentable', polymorphic => True;
  }
}

class AddRefNoIndex is Migration {
  method change {
    self.add-reference: '_ref_posts', 'author', index => False;
  }
}

class AddUniqueRef is Migration {
  method change {
    self.add-reference: '_ref_posts', 'slug', unique => True;
  }
}

class AddNotNullRef is Migration {
  method change {
    self.add-reference: '_ref_posts', 'tag', null => False, index => False;
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'migration references', :order<defined>, {
  if !$has-db { pending 'no database connection available'; }

  before-all { if $has-db { cleanup-tables; RefCreateUsers.new.up; RefCreatePosts.new.up } }
  after-all  { if $has-db { cleanup-tables } }

  context 'add-reference', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $has-db { AddUserRef.new.up } }

      it 'adds the <name>_id column', {
        expect('user_id' (elem) column-names('_ref_posts')).to.be-truthy;
      }

      it 'adds the default <table>_<name>_id_idx index', {
        expect(index-exists('_ref_posts_user_id_idx')).to.be-truthy;
      }
    }

    context 'after down (auto-inverts)', :order<defined>, {
      before-all { if $has-db { AddUserRef.new.down } }

      it 'removes the column', {
        expect('user_id' (elem) column-names('_ref_posts')).to.be-falsy;
      }

      it 'removes the index', {
        expect(index-exists('_ref_posts_user_id_idx')).to.be-falsy;
      }
    }
  }

  context 'add-belongs-to alias', :order<defined>, {
    before-all { if $has-db { AddOwnerBelongsTo.new.up } }
    after-all  { if $has-db { AddOwnerBelongsTo.new.down } }

    it 'adds the <name>_id column', {
      expect('owner_id' (elem) column-names('_ref_posts')).to.be-truthy;
    }
  }

  context 'polymorphic add-reference', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $has-db { AddCommentablePoly.new.up } }

      it 'adds the <name>_id column', {
        expect('commentable_id' (elem) column-names('_ref_posts')).to.be-truthy;
      }

      it 'adds the <name>_type column', {
        expect('commentable_type' (elem) column-names('_ref_posts')).to.be-truthy;
      }

      it 'adds the composite (type, id) index', {
        expect(index-exists('_ref_posts_commentable_type_commentable_id_idx')).to.be-truthy;
      }
    }

    context 'after down (auto-inverts)', :order<defined>, {
      before-all { if $has-db { AddCommentablePoly.new.down } }

      it 'removes the <name>_id column', {
        expect('commentable_id' (elem) column-names('_ref_posts')).to.be-falsy;
      }

      it 'removes the <name>_type column', {
        expect('commentable_type' (elem) column-names('_ref_posts')).to.be-falsy;
      }
    }
  }

  context 'add-reference with index => False', :order<defined>, {
    before-all { if $has-db { AddRefNoIndex.new.up } }
    after-all  { if $has-db { AddRefNoIndex.new.down } }

    it 'still adds the column', {
      expect('author_id' (elem) column-names('_ref_posts')).to.be-truthy;
    }

    it 'skips creating the index', {
      expect(index-exists('_ref_posts_author_id_idx')).to.be-falsy;
    }
  }

  context 'add-reference with unique => True', :order<defined>, {
    before-all { if $has-db { AddUniqueRef.new.up } }
    after-all  { if $has-db { AddUniqueRef.new.down } }

    it 'creates the unique index', {
      expect(index-exists('_ref_posts_slug_id_idx')).to.be-truthy;
    }

    it 'enforces uniqueness on <name>_id', {
      $adapter.exec("INSERT INTO _ref_posts (title, slug_id) VALUES ('a', 1)");
      expect({ $adapter.exec("INSERT INTO _ref_posts (title, slug_id) VALUES ('b', 1)") }).to.raise-error;
    }
  }

  context 'add-reference with null => False', :order<defined>, {
    before-all {
      if $has-db {
        $adapter.exec("DELETE FROM _ref_posts");
        AddNotNullRef.new.up;
      }
    }
    after-all { if $has-db { AddNotNullRef.new.down } }

    it 'makes <name>_id NOT NULL', {
      expect({ $adapter.exec("INSERT INTO _ref_posts (title) VALUES ('x')") }).to.raise-error;
    }
  }
}
