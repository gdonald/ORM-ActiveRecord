use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::PresenceOnUpdate;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'presence on: :update', {
  after-each { Game.destroy-all }

  context 'first create with no name', {
    it 'still gets an id (validation does not fire on create for name)', {
      my $game = Game.create({year => 1987});
      expect($game.id).to.be-truthy;
    }

    it 'has empty name', {
      my $game = Game.create({year => 1987});
      expect($game.name).to.eq('');
    }

    it 'is invalid on a subsequent update', {
      my $game = Game.create({year => 1987});
      expect($game.is-invalid).to.be-truthy;
    }

    it 'fails save when invalid', {
      my $game = Game.create({year => 1987});
      expect($game.save).to.be-falsy;
    }
  }

  context 'second create with no name (separate record)', {
    it 'still gets an id', {
      my $game = Game.create({year => 1987});
      expect($game.id).to.be-truthy;
    }

    it 'has empty name', {
      my $game = Game.create({year => 1987});
      expect($game.name).to.eq('');
    }

    it 'is invalid on subsequent check', {
      my $game = Game.create({year => 1987});
      expect($game.is-invalid).to.be-truthy;
    }

    it 'fails save', {
      my $game = Game.create({year => 1987});
      expect($game.save).to.be-falsy;
    }
  }

  context 'create with explicit Nil name', {
    it 'still gets an id', {
      my $game = Game.create({name => Nil, year => 1987});
      expect($game.id).to.be-truthy;
    }

    it 'has no name', {
      my $game = Game.create({name => Nil, year => 1987});
      expect($game.name).to.be-falsy;
    }

    it 'is invalid for update', {
      my $game = Game.create({name => Nil, year => 1987});
      expect($game.is-invalid).to.be-truthy;
    }

    it 'fails save', {
      my $game = Game.create({name => Nil, year => 1987});
      expect($game.save).to.be-falsy;
    }

    it 'remains invalid after a failed save', {
      my $game = Game.create({name => Nil, year => 1987});
      $game.save;
      expect($game.is-invalid).to.be-truthy;
    }
  }

  context 'create with name "Frogger"', {
    it 'has name "Frogger"', {
      my $game = Game.create({name => 'Frogger', year => 1987});
      expect($game.name).to.eq('Frogger');
    }
  }

  context 'updating Frogger to Super Metroid', {
    it 'updates the in-memory name', {
      my $game = Game.create({name => 'Frogger', year => 1987});
      $game.name = 'Super Metroid';
      expect($game.name).to.eq('Super Metroid');
    }

    it 'saves successfully', {
      my $game = Game.create({name => 'Frogger', year => 1987});
      $game.name = 'Super Metroid';
      expect($game.save).to.be-truthy;
    }

    it 'preserves the name after save', {
      my $game = Game.create({name => 'Frogger', year => 1987});
      $game.name = 'Super Metroid';
      $game.save;
      expect($game.name).to.eq('Super Metroid');
    }

    it 'has no fname error (typo from original test preserved)', {
      my $game = Game.create({name => 'Frogger', year => 1987});
      $game.name = 'Super Metroid';
      $game.save;
      expect($game.errors.fname).to.be-falsy;
    }
  }

  context 'create-without-name then set + save', {
    it 'updates the in-memory name', {
      my $game = Game.create({year => 1987});
      $game.name = 'Super Metroid';
      expect($game.name).to.eq('Super Metroid');
    }

    it 'saves successfully', {
      my $game = Game.create({year => 1987});
      $game.name = 'Super Metroid';
      expect($game.save).to.be-truthy;
    }

    it 'preserves the name after save', {
      my $game = Game.create({year => 1987});
      $game.name = 'Super Metroid';
      $game.save;
      expect($game.name).to.eq('Super Metroid');
    }

    it 'has no name error', {
      my $game = Game.create({year => 1987});
      $game.name = 'Super Metroid';
      $game.save;
      expect($game.errors.name).to.be-falsy;
    }
  }
}
