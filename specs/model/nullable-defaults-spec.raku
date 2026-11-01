use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use Defaults::NullableColumns;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'the starting value of a column the caller does not set', {
  after-each {
    Ward.destroy-all;
    Guardian.destroy-all;
  }

  context 'a nullable integer column', {
    let(:ward, { Ward.build({ name => 'Ada', slot => 1 }) });

    it 'starts undefined on a new record', {
      expect(ward.score.defined).to.be-falsy;
    }

    it 'stores NULL', {
      ward.save;

      expect(Ward.find(ward.id).score.defined).to.be-falsy;
    }
  }

  context 'a nullable string column', {
    let(:ward, { Ward.build({ name => 'Ada', slot => 1 }) });

    it 'stores NULL', {
      ward.save;

      expect(Ward.find(ward.id).nickname.defined).to.be-falsy;
    }
  }

  context 'a nullable foreign key with a constraint', {
    let(:ward, { Ward.create({ name => 'Ada', slot => 1 }) });

    it 'saves without a guardian', {
      expect(ward.is-persisted).to.be-truthy;
    }

    it 'stores NULL', {
      expect(Ward.find(ward.id).guardian_id.defined).to.be-falsy;
    }
  }

  context 'a nullable foreign key set by the caller', {
    let(:guardian, { Guardian.create({ name => 'Bea' }) });
    let(:ward, { Ward.create({ name => 'Ada', slot => 1, guardian_id => guardian.id }) });

    it 'stores the guardian', {
      expect(Ward.find(ward.id).guardian_id).to.eq(guardian.id);
    }
  }

  context 'a column with a database default', {
    let(:ward, { Ward.create({ name => 'Ada', slot => 1 }) });

    it 'starts at the database default on a new record', {
      expect(Ward.build({ name => 'Ada' }).tier).to.eq(3);
    }

    it 'gets the database default', {
      expect(Ward.find(ward.id).tier).to.eq(3);
    }
  }

  context 'a NOT NULL column with no default', {
    let(:ward, { Ward.build({ name => 'Ada' }) });

    it 'starts at the value for its type', {
      expect(ward.slot).to.eq(0);
    }

    it 'stores the value for its type', {
      ward.save;

      expect(Ward.find(ward.id).slot).to.eq(0);
    }
  }

  context 'comparing records with ==', {
    let(:ward, { Ward.create({ name => 'Ada', slot => 1 }) });

    it 'matches a reload whose nullable column is NULL', {
      expect(Ward.find(ward.id) == ward).to.be-truthy;
    }

    context 'when the other record has a value in that column', {
      let(:scored, { Ward.find(ward.id) });

      before-each { scored.score = 7 }

      it 'does not match', {
        expect(ward() == scored).to.be-falsy;
      }
    }
  }

  context 'dirty tracking on a new record', {
    let(:ward, { Ward.build({ name => 'Ada', slot => 1 }) });

    before-each { ward.score = 7 }

    it 'reports the change from undefined', {
      expect(ward.attribute-change('score')[0].defined).to.be-falsy;
    }
  }
}
