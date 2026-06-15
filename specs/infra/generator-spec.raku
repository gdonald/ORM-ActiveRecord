use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Schema::Generator;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'code generators', {
  my $gen = Generator.new(:stamp('20260615120000'));

  context 'naming helpers', {
    it 'classizes underscored names to PascalCase', {
      expect($gen.classize('blog_post')).to.eq('BlogPost');
    }

    it 'kebabizes camel-case names', {
      expect($gen.kebabize('AddEmailToUsers')).to.eq('add-email-to-users');
    }

    it 'tableizes with the ORM naive plural rule', {
      expect($gen.tableize('Person')).to.eq('persons');
    }
  }

  context 'model rendering', {
    let(:model, { $gen.render-model('User', ['name:string', 'role:references']) });

    it 'renders the model class', {
      expect(model.contains('class User is Model')).to.be-truthy;
    }

    it 'turns a reference field into a belongs-to', {
      expect(model.contains("self.belongs-to: role => class-name => 'Role'")).to.be-truthy;
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

    it 'renders an empty stub for an unrecognised name', {
      my $out = $gen.render-migration('Frobnicate', []);
      expect($out.contains('class Frobnicate is Migration')).to.be-truthy;
    }
  }

  context 'validator rendering', {
    it 'appends Validator to the class name', {
      expect($gen.render-validator('NotEvil').contains('class NotEvilValidator is export')).to.be-truthy;
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
}
