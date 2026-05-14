
use ORM::ActiveRecord::DB;

role QueryBatching is export {
  method find-in-batches(Int:D :$batch-size = 1000) {
    die "find-in-batches: batch-size must be > 0" if $batch-size <= 0;
    return Seq.new(().iterator) if self.is-none-value;

    my $table       = self.table-of;
    my $class       = self.class-of;
    my @fields      = self.fields-of;
    my %where-base  = %( self.where-values );
    my %where-not   = self.where-not-values;
    my @or-groups   = self.or-groups-payload;
    my $distinct    = self.distinct-value;
    my @group       = self.group-values;
    my @having      = self.having-values;
    my $from-source = self.from-source;
    my $from-alias  = self.from-alias;
    my @joins       = self.joins-values;
    my @ctes        = self.ctes-values;
    my @annotations = self.annotations-values;
    my @optimizer-hints = self.optimizer-hints-values;
    my $readonly    = self.readonly-value;

    gather {
      my $cursor = 0;
      loop {
        my %w = %where-base;
        %w<id> = Range.new($cursor, Inf, :excludes-min);
        my @order = ('id ASC',);
        my @objects = DB.shared.get-objects(
          :$table, :$class, :@fields,
          where => %w, where-not => %where-not, :@or-groups,
          :@order, limit => $batch-size, offset => 0,
          distinct => $distinct,
          group => @group, having => @having,
          from-source => $from-source, from-alias => $from-alias,
          joins => @joins,
          :@ctes, :@annotations, :@optimizer-hints,
        );
        last unless @objects.elems;
        if $readonly { .make-readonly for @objects }
        take @objects.Array;
        last if @objects.elems < $batch-size;
        $cursor = @objects[*-1].id;
      }
    }
  }

  method find-each(Int:D :$batch-size = 1000) {
    gather for self.find-in-batches(:$batch-size) -> @batch {
      take $_ for @batch;
    }
  }

  method in-batches(Int:D :$of = 1000, Bool:D :$load = False) {
    die "in-batches: :of must be > 0" if $of <= 0;
    return Seq.new(().iterator) if self.is-none-value;

    gather {
      my $cursor = 0;
      loop {
        my $batch = self.clone-query;
        $batch.where({ id => Range.new($cursor, Inf, :excludes-min) });
        $batch.reorder('id ASC');
        $batch.limit($of);

        my @objects = $batch.perform;
        last unless @objects.elems;

        if $load {
          take @objects.Array;
        } else {
          take $batch;
        }

        last if @objects.elems < $of;
        $cursor = @objects[*-1].id;
      }
    }
  }
}
