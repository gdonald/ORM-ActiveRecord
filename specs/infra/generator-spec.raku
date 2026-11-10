use BDD::Behave;
use JSON::Fast;
use ORM::ActiveRecord::Schema::Generator;

%*ENV<DISABLE-SQL-LOG> = True;

sub write-meta(IO::Path $dir) {
  $dir.add('META6.json').spurt: to-json({
    name     => 'demo',
    provides => { Existing => 'app/models/Existing.rakumod' },
  });
}

describe 'code generators', {
  my $gen = Generator.new(:stamp('20260615120000'));

  context 'naming helpers', {
    it 'classizes underscored names to PascalCase', {
      expect($gen.classize('blog_post')).to.eq('BlogPost');
    }

    it 'kebabizes camel-case names', {
      expect($gen.kebabize('AddEmailToUsers')).to.eq('add-email-to-users');
    }

    it 'tableizes an irregular name with the inflector', {
      expect($gen.tableize('Person')).to.eq('people');
    }

    it 'tableizes a consonant y name with the inflector', {
      expect($gen.tableize('Category')).to.eq('categories');
    }

    it 'tableizes a camel-case name to snake_case plural', {
      expect($gen.tableize('PageTag')).to.eq('page_tags');
    }

    it 'tableizes an underscored name to snake_case plural', {
      expect($gen.tableize('blog_post')).to.eq('blog_posts');
    }
  }

  context 'model rendering', {
    let(:model, { $gen.render-model('User', ['name:string', 'role:references', 'blog_post:references']) });

    it 'renders the model class', {
      expect(model.contains('class User is Model')).to.be-truthy;
    }

    it 'turns a reference field into a belongs-to without a class name', {
      expect(model.contains('self.belongs-to: :role;')).to.be-truthy;
    }

    it 'turns an underscored reference field into a dashed belongs-to', {
      expect(model.contains('self.belongs-to: :blog-post;')).to.be-truthy;
    }

    it 'leaves class-name out of the belongs-to declarations', {
      expect(model.contains('class-name')).to.be-falsy;
    }

    it 'registers the class in GLOBAL', {
      expect(model.contains('GLOBAL::<User> := User;')).to.be-truthy;
    }
  }

  context 'migration rendering', {
    it 'renders a create-table migration', {
      my $out = $gen.render-migration('CreateWidgets', ['name:string', 'slug:string:uniq']);
      expect($out.contains("self.create-table: 'widgets'")).to.be-truthy;
    }

    it 'emits an inline unique for the uniq modifier', {
      my $out = $gen.render-migration('CreateWidgets', ['slug:string:uniq']);
      expect($out.contains('unique => True')).to.be-truthy;
    }

    it 'renders an add-column migration from the name', {
      my $out = $gen.render-migration('AddEmailToUsers', ['email:string']);
      expect($out.contains("self.add-column: 'users', :email")).to.be-truthy;
    }

    it 'renders a remove-column migration from the name', {
      my $out = $gen.render-migration('RemovePriceFromWidgets', ['price:decimal']);
      expect($out.contains("self.remove-column: 'widgets', :price;")).to.be-truthy;
    }

    it 'renders an empty stub for an unrecognized name', {
      my $out = $gen.render-migration('Frobnicate', []);
      expect($out.contains('class Frobnicate is Migration')).to.be-truthy;
    }
  }

  context 'validator rendering', {
    it 'appends Validator to the class name', {
      expect($gen.render-validator('NotEvil').contains('class NotEvilValidator is export')).to.be-truthy;
    }
  }

  context 'rendered file beginnings', {
    it 'starts a model with a use statement', {
      expect($gen.render-model('User', ['name:string']).starts-with('use ')).to.be-truthy;
    }

    it 'starts a create-table migration with a use statement', {
      expect($gen.render-migration('CreateWidgets', ['name:string']).starts-with('use ')).to.be-truthy;
    }

    it 'starts an add-column migration with a use statement', {
      expect($gen.render-migration('AddEmailToUsers', ['email:string']).starts-with('use ')).to.be-truthy;
    }

    it 'starts a remove-column migration with a use statement', {
      expect($gen.render-migration('RemovePriceFromWidgets', ['price:decimal']).starts-with('use ')).to.be-truthy;
    }

    it 'starts an empty migration with a use statement', {
      expect($gen.render-migration('Frobnicate', []).starts-with('use ')).to.be-truthy;
    }

    it 'starts a validator with a use statement', {
      expect($gen.render-validator('NotEvil').starts-with('use ')).to.be-truthy;
    }
  }

  context 'scope rendering', {
    it 'builds the where conditions', {
      expect($gen.render-scope-line('active', ['published:True']).contains('published => True')).to.be-truthy;
    }
  }

  context 'writing and removing files', {
    let(:work, {
      my $tmp = $*TMPDIR.add('ar-generator-spec-' ~ $*PID);
      $tmp.mkdir;
      $tmp;
    });

    let(:writer, { Generator.new(:root(work.Str), :stamp('20260615120000')) });

    it 'writes a model and a create migration', {
      writer.generate-model('Account', ['name:string']);

      aggregate-failures {
        expect(work.add('app/models/Account.rakumod').e).to.be-truthy;
        expect(work.add('db/migrate/20260615120000-create-accounts.raku').e).to.be-truthy;
      }

      run 'rm', '-rf', work.Str;
    }

    it 'removes the validator file on destroy', {
      writer.generate-validator('Strong');
      writer.destroy-validator('Strong');
      expect(work.add('app/validators/StrongValidator.rakumod').e).to.be-falsy;

      run 'rm', '-rf', work.Str;
    }
  }

  context 'versioning migrations without a fixed stamp', {
    let(:work, {
      my $tmp = $*TMPDIR.add('ar-generator-version-spec-' ~ $*PID);
      $tmp.mkdir;
      $tmp;
    });

    let(:writer, { Generator.new(:root(work.Str)) });

    it 'gives back-to-back migrations different versions', {
      my $form       = writer.generate-model('Form', ['name:string'])[1].IO.basename.substr(0, 14);
      my $form-field = writer.generate-model('FormField', ['label:string'])[1].IO.basename.substr(0, 14);

      expect($form-field > $form).to.be-truthy;

      run 'rm', '-rf', work.Str;
    }

    it 'starts one second after a migration version later than the current time', {
      work.add('db/migrate').mkdir;
      work.add('db/migrate/20991231235959-create-reports.raku').spurt('');

      my @paths = writer.generate-migration('AddTitleToReports', ['title:string']);
      expect(@paths[0].IO.basename).to.eq('21000101000000-add-title-to-reports.raku');

      run 'rm', '-rf', work.Str;
    }
  }

  context 'adding a generated model to META6.json provides', {
    let(:work, {
      my $tmp = $*TMPDIR.add('ar-generator-provides-' ~ $*PID);
      $tmp.mkdir;
      $tmp;
    });

    let(:writer, { Generator.new(:root(work.Str), :stamp('20260615120000')) });

    context 'when the project has a META6.json', {
      it 'maps the model class to its file', {
        write-meta(work);
        writer.generate-model('Widget', ['name:string']);
        writer.provide-model('Widget');

        expect(from-json(work.add('META6.json').slurp)<provides><Widget>).to.eq('app/models/Widget.rakumod');

        run 'rm', '-rf', work.Str;
      }

      it 'keeps the other provides entries', {
        write-meta(work);
        writer.provide-model('Widget');

        expect(from-json(work.add('META6.json').slurp)<provides><Existing>).to.eq('app/models/Existing.rakumod');

        run 'rm', '-rf', work.Str;
      }

      it 'writes the keys in sorted order', {
        write-meta(work);
        writer.provide-model('Widget');

        my $json = work.add('META6.json').slurp;
        expect($json.index('"Existing"') < $json.index('"Widget"')).to.be-truthy;

        run 'rm', '-rf', work.Str;
      }

      it 'reports that it added the entry', {
        write-meta(work);

        expect(writer.provide-model('Widget')).to.be-truthy;

        run 'rm', '-rf', work.Str;
      }

      it 'reports no change when the entry is already present', {
        write-meta(work);
        writer.provide-model('Widget');

        expect(writer.provide-model('Widget')).to.be-falsy;

        run 'rm', '-rf', work.Str;
      }
    }

    context 'when the project has no META6.json', {
      it 'reports no change', {
        expect(writer.provide-model('Widget')).to.be-falsy;

        run 'rm', '-rf', work.Str;
      }

      it 'does not create a META6.json', {
        writer.provide-model('Widget');

        expect(work.add('META6.json').e).to.be-falsy;

        run 'rm', '-rf', work.Str;
      }
    }
  }
}
