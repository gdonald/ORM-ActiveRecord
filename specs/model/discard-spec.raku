use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Discard::Models;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'soft deletes / discard', {
  before-each {
    Notice.destroy-all;
    Parcel.destroy-all;
    @Discard::Models::discard-events = [];
  }

  after-each {
    Notice.destroy-all;
    Parcel.destroy-all;
  }

  context 'discard on a record', {
    it 'marks the record as discarded', {
      my $notice = Notice.create({name => 'sale'});
      $notice.discard;
      expect($notice.is-discarded).to.be-truthy;
    }

    it 'sets the configured timestamp column', {
      my $notice = Notice.create({name => 'sale'});
      $notice.discard;
      expect($notice.deleted_at).to.be-truthy;
    }

    it 'returns False when the record is already discarded', {
      my $notice = Notice.create({name => 'sale'});
      $notice.discard;
      expect($notice.discard).to.be-falsy;
    }

    it 'leaves the row in the table', {
      my $notice = Notice.create({name => 'sale'});
      $notice.discard;
      expect(Notice.with-discarded.count).to.eq(1);
    }
  }

  context 'undiscard on a discarded record', {
    it 'clears the discarded state', {
      my $notice = Notice.create({name => 'sale'});
      $notice.discard;
      $notice.undiscard;
      expect($notice.is-kept).to.be-truthy;
    }

    it 'clears the timestamp column', {
      my $notice = Notice.create({name => 'sale'});
      $notice.discard;
      $notice.undiscard;
      expect($notice.deleted_at.defined).to.be-falsy;
    }

    it 'returns False when the record is not discarded', {
      my $notice = Notice.create({name => 'sale'});
      expect($notice.undiscard).to.be-falsy;
    }
  }

  context 'kept and discarded class scopes', {
    before-each {
      my $kept = Notice.create({name => 'kept'});
      my $gone = Notice.create({name => 'gone'});
      $gone.discard;
    }

    it 'kept returns only the undiscarded rows', {
      expect(Notice.kept.count).to.eq(1);
    }

    it 'discarded returns only the discarded rows', {
      expect(Notice.discarded.count).to.eq(1);
    }

    it 'with-discarded returns every row', {
      expect(Notice.with-discarded.count).to.eq(2);
    }
  }

  context 'discard-all and undiscard-all', {
    before-each {
      Notice.create({name => 'one'});
      Notice.create({name => 'two'});
    }

    it 'discard-all discards every kept row', {
      Notice.discard-all;
      expect(Notice.discarded.count).to.eq(2);
    }

    it 'undiscard-all restores every discarded row', {
      Notice.discard-all;
      Notice.undiscard-all;
      expect(Notice.kept.count).to.eq(2);
    }
  }

  context 'discard callbacks', {
    it 'fires before-discard and after-discard in order', {
      my $notice = Notice.create({name => 'sale'});
      $notice.discard;
      expect(@Discard::Models::discard-events).to.eq(['before-discard', 'after-discard']);
    }

    it 'fires after-undiscard on undiscard', {
      my $notice = Notice.create({name => 'sale'});
      $notice.discard;
      @Discard::Models::discard-events = [];
      $notice.undiscard;
      expect(@Discard::Models::discard-events).to.eq(['after-undiscard']);
    }

    it 'aborts the discard when before-discard returns False', {
      my $locked = Locked.create({name => 'sale'});
      $locked.discard;
      expect($locked.is-discarded).to.be-falsy;
    }
  }

  context 'opt-in default scope hiding discarded rows', {
    before-each {
      my $kept = Parcel.create({name => 'kept'});
      my $gone = Parcel.create({name => 'gone'});
      $gone.discard;
    }

    it 'hides discarded rows from the default relation', {
      expect(Parcel.all.elems).to.eq(1);
    }

    it 'reveals discarded rows through with-discarded', {
      expect(Parcel.with-discarded.count).to.eq(2);
    }

    it 'reveals discarded rows through discarded', {
      expect(Parcel.discarded.count).to.eq(1);
    }
  }
}
