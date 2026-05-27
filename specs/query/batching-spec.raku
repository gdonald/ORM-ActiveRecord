use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Relation::Query;

%*ENV<DISABLE-SQL-LOG> = True;

class BtUser is Model {
  method table-name { 'users' }
}

describe 'batching', {
  my @expected-ids;

  before-each {
    BtUser.destroy-all;
    my @created;
    for 1..12 -> $i {
      @created.push: BtUser.create({fname => "F$i", lname => "L$i"});
    }
    @expected-ids = @created.map(*.id).sort;
  }

  after-each {
    BtUser.destroy-all;
  }

  context 'find-each', {
    it 'yields every record', {
      my @seen-ids;
      for BtUser.find-each(:batch-size(5)) -> $u {
        @seen-ids.push: $u.id;
      }

      expect(@seen-ids.elems).to.eq(12);
    }

    it 'covers all ids', {
      my @seen-ids;
      for BtUser.find-each(:batch-size(5)) -> $u {
        @seen-ids.push: $u.id;
      }

      expect(@seen-ids.sort.join(',')).to.eq(@expected-ids.join(','));
    }

    it 'does not duplicate records', {
      my @seen-ids;
      for BtUser.find-each(:batch-size(5)) -> $u {
        @seen-ids.push: $u.id;
      }

      expect(@seen-ids.unique.elems).to.eq(12);
    }

    it 'yields rows in id ASC order', {
      my @seen-ids;
      for BtUser.find-each(:batch-size(5)) -> $u {
        @seen-ids.push: $u.id;
      }

      expect(@seen-ids.join(',')).to.eq(@seen-ids.sort.join(','));
    }

    it 'honors WHERE filter with default batch-size', {
      my @small;
      for BtUser.where({fname => ['F1', 'F2', 'F3']}).find-each -> $u {
        @small.push: $u.id;
      }

      expect(@small.elems).to.eq(3);
    }
  }

  context 'find-in-batches', {
    it 'produces ceil(12/5) = 3 batches', {
      my @batches;
      for BtUser.find-in-batches(:batch-size(5)) -> @batch {
        @batches.push: @batch.elems;
      }

      expect(@batches.elems).to.eq(3);
    }

    it 'batch sizes are 5, 5, 2', {
      my @batches;
      for BtUser.find-in-batches(:batch-size(5)) -> @batch {
        @batches.push: @batch.elems;
      }

      expect(@batches[0] == 5 && @batches[1] == 5 && @batches[2] == 2).to.be-truthy;
    }

    it 'batch-size = row count emits one batch', {
      my @one-batch;
      for BtUser.find-in-batches(:batch-size(12)) -> @batch {
        @one-batch.push: @batch;
      }

      expect(@one-batch.elems == 1 && @one-batch[0].elems == 12).to.be-truthy;
    }

    it 'batch-size > row count emits one batch', {
      my @over;
      for BtUser.find-in-batches(:batch-size(50)) -> @batch {
        @over.push: @batch.elems;
      }

      expect(@over.elems == 1 && @over[0] == 12).to.be-truthy;
    }

    it 'honors WHERE', {
      my @filtered;
      for BtUser.where({fname => ['F1','F2','F3','F4','F5','F6','F7']}).find-in-batches(:batch-size(3)) -> @batch {
        @filtered.push: @batch.elems;
      }

      expect(@filtered.elems == 3 && @filtered[0] == 3 && @filtered[1] == 3 && @filtered[2] == 1).to.be-truthy;
    }
  }

  context 'in-batches', {
    it 'yields 3 relations for 12 rows / 5', {
      my @relations;
      for BtUser.in-batches(:of(5)) -> $rel {
        @relations.push: $rel;
      }

      expect(@relations.elems).to.eq(3);
    }

    it 'yields Query objects', {
      my @relations;
      for BtUser.in-batches(:of(5)) -> $rel {
        @relations.push: $rel;
      }

      expect(@relations.all ~~ Query).to.be-truthy;
    }

    it 'first batch relation has 5 rows', {
      my @relations;
      for BtUser.in-batches(:of(5)) -> $rel {
        @relations.push: $rel;
      }

      expect(@relations[0].all.elems).to.eq(5);
    }

    it 'last batch relation has remainder', {
      my @relations;
      for BtUser.in-batches(:of(5)) -> $rel {
        @relations.push: $rel;
      }

      expect(@relations[2].all.elems).to.eq(2);
    }

    it 'relations cover all rows', {
      my @rel-ids;
      for BtUser.in-batches(:of(4)) -> $rel {
        @rel-ids.append: $rel.ids;
      }

      expect(@rel-ids.elems).to.eq(12);
    }

    it 'relations cover all ids', {
      my @rel-ids;
      for BtUser.in-batches(:of(4)) -> $rel {
        @rel-ids.append: $rel.ids;
      }

      expect(@rel-ids.sort.join(',')).to.eq(@expected-ids.join(','));
    }

    it 'with :load yields arrays sized by :of', {
      my @loaded;
      for BtUser.in-batches(:of(5), :load) -> @batch {
        @loaded.push: @batch.elems;
      }

      expect(@loaded.elems == 3 && @loaded[0] == 5 && @loaded[2] == 2).to.be-truthy;
    }
  }

  context 'none short-circuits', {
    it 'find-each on none is empty', {
      my @nothing;
      for BtUser.none.find-each -> $u { @nothing.push: $u }

      expect(@nothing.elems).to.eq(0);
    }

    it 'find-in-batches on none is empty', {
      my @no-batches;
      for BtUser.none.find-in-batches(:batch-size(5)) -> @b { @no-batches.push: @b }

      expect(@no-batches.elems).to.eq(0);
    }

    it 'in-batches on none is empty', {
      my @no-rels;
      for BtUser.none.in-batches(:of(5)) -> $r { @no-rels.push: $r }

      expect(@no-rels.elems).to.eq(0);
    }
  }

  context 'invalid batch size', {
    it 'find-in-batches with batch-size 0 dies', {
      expect({
        for BtUser.find-in-batches(:batch-size(0)) -> @b { }
      }).to.raise-error;
    }

    it 'in-batches with :of <= 0 dies', {
      expect({
        for BtUser.in-batches(:of(-1)) -> $r { }
      }).to.raise-error;
    }
  }
}
