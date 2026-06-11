
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Utils;

role ModelFinders is export {
  method find(*@rest) {
    my @pk = self.primary-keys;

    if @pk.elems > 1 || @pk[0] ne 'id' {
      my @vals = @rest.elems == 1 && @rest[0] ~~ Positional ?? @rest[0].list !! @rest.list;
      die X::RecordNotFound.new(:model(Utils.base-name(self.WHAT.^name)))
        unless @vals.elems == @pk.elems;

      my %where = (@pk Z=> @vals).hash;
      my $obj = self.where(%where).first;
      die X::RecordNotFound.new(:model(Utils.base-name(self.WHAT.^name)), :id(@vals.join(',')))
        without $obj;
      return $obj;
    }

    my Int $id = 0;
    $id = @rest[0] if @rest.elems == 1 && @rest[0].isa(Int);
    my $obj = self.new(:$id);
    die X::RecordNotFound.new(:model(Utils.base-name(self.WHAT.^name)), :$id)
      unless $obj.attrs<id>;
    $obj;
  }

  method find-by(Hash:D $params) {
    self.where($params).first;
  }

  method find-by-bang(Hash:D $params) {
    my $obj = self.find-by($params);
    die X::RecordNotFound.new(:model(Utils.base-name(self.WHAT.^name))) without $obj;
    $obj;
  }

  method sole {
    self.all.sole;
  }

  method find-sole-by(Hash:D $params) {
    self.where($params).sole;
  }

  method find-or-create-by(Hash:D $params) {
    self.all.find-or-create-by($params);
  }

  method find-or-create-by-bang(Hash:D $params) {
    self.all.find-or-create-by-bang($params);
  }

  method find-or-initialize-by(Hash:D $params) {
    self.all.find-or-initialize-by($params);
  }

  method create-with(Hash:D $attrs) {
    self.all.create-with($attrs);
  }

  multi method first                { self.all.first }
  multi method first(Int:D $n)      { self.all.first($n) }
  multi method last                 { self.all.last }
  multi method last(Int:D $n)       { self.all.last($n) }

  method take(Int:D $limit = 1) {
    my $table = Utils.table-name(self);
    my @fields = self.db.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
    my %where;
    self.db.get-objects(:$table, class => self.WHAT, :@fields, :%where, :$limit);
  }

  multi method exists(Hash:D $params) {
    self.where($params).count > 0;
  }

  multi method exists {
    self.count > 0;
  }
}
