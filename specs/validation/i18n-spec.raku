use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::I18n;
use Validation::I18n;

%*ENV<DISABLE-SQL-LOG> = True;

sub load-french {
  I18n.store('fr', {
    errors => {
      messages => {
        blank          => 'doit être rempli',
        'too-long'     => 'est trop long (maximum {count} caractères)',
        'greater-than' => 'doit être supérieur à {count}',
        taken          => '{model} existe déjà',
      },
    },
    activerecord => {
      errors => {
        models => {
          recital => {
            attributes => {
              name => { blank => 'le nom est obligatoire' },
            },
          },
        },
      },
    },
  });
}

describe 'locale-driven error messages', {
  before-each {
    Recital.destroy-all;
    I18n.reset;
    load-french;
  }

  after-each {
    Recital.destroy-all;
    I18n.reset;
  }

  context 'with the current locale set to a registered locale', {
    before-each { I18n.set-locale('fr') }

    it 'resolves a message-level template for the error type', {
      my $r = Recital.build({name => 'ok', max_score => 0});
      $r.is-invalid;
      expect($r.errors.max_score[0]).to.eq('doit être supérieur à 1');
    }

    it 'prefers a model-and-attribute-specific template over the message-level one', {
      my $r = Recital.build({name => '', max_score => 5});
      $r.is-invalid;
      expect($r.errors.name[0]).to.eq('le nom est obligatoire');
    }

    it 'interpolates the count token in a length template', {
      my $r = Recital.build({name => 'abcd', max_score => 5});
      $r.is-invalid;
      expect($r.errors.name[0]).to.eq('est trop long (maximum 3 caractères)');
    }
  }

  context 'with the default English locale', {
    it 'falls back to the built-in template', {
      my $r = Recital.build({name => 'ok', max_score => 0});
      $r.is-invalid;
      expect($r.errors.max_score[0]).to.eq('more than 1 required');
    }
  }

  context 'with-locale running a block under a temporary locale', {
    it 'uses the temporary locale inside the block', {
      my $message;

      I18n.with-locale('fr', {
        my $r = Recital.build({name => '', max_score => 5});
        $r.is-invalid;
        $message = $r.errors.name[0];
      });

      expect($message).to.eq('le nom est obligatoire');
    }

    it 'restores the previous locale after the block', {
      I18n.set-locale('en');
      I18n.with-locale('fr', sub { });
      expect(I18n.locale).to.eq('en');
    }
  }

  context 'errors added directly on the collection', {
    before-each { I18n.set-locale('fr') }

    it 'resolves the template from the locale store', {
      my $r = Recital.build({name => 'ok', max_score => 5});
      $r.errors.add('name', 'blank');
      expect($r.errors.name[0]).to.eq('le nom est obligatoire');
    }

    it 'interpolates the model token from the owning record', {
      my $r = Recital.build({name => 'ok', max_score => 5});
      $r.errors.add('name', 'taken');
      expect($r.errors.name[0]).to.eq('Recital existe déjà');
    }
  }
}
