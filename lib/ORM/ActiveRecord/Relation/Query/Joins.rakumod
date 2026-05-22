
use ORM::ActiveRecord::Support::Utils;

role QueryJoins is export {
  method joins(*@args, *%kw) {
    self!collect-joins('INNER JOIN', @args, %kw);
    self;
  }

  method left-outer-joins(*@args, *%kw) {
    self!collect-joins('LEFT OUTER JOIN', @args, %kw);
    self;
  }

  method !collect-joins(Str:D $kind, @args, %kw) {
    for @args -> $a {
      self!add-join-arg($kind, $a, self.class-of, self.table-of);
    }
    for %kw.kv -> $k, $v {
      self!add-named-join($kind, $k, $v, self.class-of, self.table-of);
    }
  }

  method !add-named-join(Str:D $kind, $k, $v, Mu $base-class, Str $base-table) {
    my ($child-class, $child-table) = self.add-assoc-join($kind, $k.Str, $base-class, $base-table);
    self!add-join-arg($kind, $v, $child-class, $child-table) unless $v === True;
  }

  method !add-join-arg(Str:D $kind, $arg, Mu $base-class, Str $base-table) {
    given $arg {
      when Pair {
        self!add-named-join($kind, $arg.key, $arg.value, $base-class, $base-table);
      }
      when Hash {
        for $arg.kv -> $k, $v {
          self!add-named-join($kind, $k, $v, $base-class, $base-table);
        }
      }
      when Iterable {
        for $arg.list -> $sub { self!add-join-arg($kind, $sub, $base-class, $base-table) }
      }
      when Str {
        if $arg.contains(' ') || $arg.contains("\t") || $arg.uc.contains('JOIN') {
          self.joins-values.push: $arg;
        } else {
          self.add-assoc-join($kind, $arg, $base-class, $base-table);
        }
      }
      when Bool { }
      default {
        self.add-assoc-join($kind, $arg.Str, $base-class, $base-table);
      }
    }
  }

  method add-assoc-join(Str:D $kind, Str:D $name, Mu $base-class, Str $base-table) {
    my $stub = $base-class.new(:id(0));
    if $stub.belongs-tos{$name}:exists {
      if $stub.is-polymorphic-assoc($name) {
        die "joins: polymorphic belongs_to '$name' on "
            ~ $base-class.^name
            ~ " cannot be joined; use preload instead of eager-load";
      }
      my $other-class = $stub.assoc-class-from-spec($stub.belongs-tos{$name});
      my $other-table = Utils.table-name($other-class);
      my $fkey = $name ~ '_id';
      self.joins-values.push: "$kind $other-table ON $other-table.id = $base-table.$fkey";
      return ($other-class, $other-table);
    }
    if $stub.has-manys{$name}:exists {
      my $hm = $stub.has-manys{$name};
      if $stub.assoc-spec-value($hm, 'through').defined {
        my $through-name = $stub.assoc-spec-value($hm, 'through').key.Str;
        my ($mid-class, $mid-table) = self.add-assoc-join($kind, $through-name, $base-class, $base-table);
        my $singular = $stub.assoc-source-name($hm, Utils.singular($name));
        my $mid-stub = $mid-class.new(:id(0));
        if $mid-stub.belongs-tos{$singular}:exists {
          if $mid-stub.is-polymorphic-assoc($singular) {
            die "joins: polymorphic source '$singular' on "
                ~ $mid-class.^name
                ~ " cannot be joined; use preload instead of eager-load";
          }
          my $other-class = $mid-stub.assoc-class-from-spec($mid-stub.belongs-tos{$singular});
          my $other-table = Utils.table-name($other-class);
          my $fkey = $singular ~ '_id';
          self.joins-values.push: "$kind $other-table ON $other-table.id = $mid-table.$fkey";
          return ($other-class, $other-table);
        }
        die "joins: cannot resolve has_many :through '$name' on " ~ $base-class.^name;
      }
      if $stub.assoc-spec-has($hm, 'as') {
        my $as-name = ~$stub.assoc-spec-value($hm, 'as');
        my $other-class = $stub.assoc-class-from-spec($hm);
        if $other-class !=== Mu {
          my $other-table = Utils.table-name($other-class);
          my $type-name = $stub.polymorphic-name;
          my $type-q = $type-name.subst("'", "''", :g);
          my $fkey = $as-name ~ '_id';
          my $tcol = $as-name ~ '_type';
          self.joins-values.push: "$kind $other-table ON $other-table.$fkey = $base-table.id AND $other-table.$tcol = '$type-q'";
          return ($other-class, $other-table);
        }
      }
      my $other-class = $stub.assoc-class-from-spec($hm);
      if $other-class !=== Mu {
        my $other-table = Utils.table-name($other-class);
        my $fkey = $stub.assoc-fkey-from-spec($hm, Utils.to-foreign-key($base-table));
        self.joins-values.push: "$kind $other-table ON $other-table.$fkey = $base-table.id";
        return ($other-class, $other-table);
      }
    }
    if $stub.has-ones{$name}:exists {
      my $ho = $stub.has-ones{$name};
      if $stub.assoc-spec-value($ho, 'through').defined {
        my $through-name = $stub.assoc-spec-value($ho, 'through').key.Str;
        my ($mid-class, $mid-table) = self.add-assoc-join($kind, $through-name, $base-class, $base-table);
        my $source = $stub.assoc-source-name($ho, $name);
        my $mid-stub = $mid-class.new(:id(0));
        if $mid-stub.belongs-tos{$source}:exists {
          if $mid-stub.is-polymorphic-assoc($source) {
            die "joins: polymorphic source '$source' on "
                ~ $mid-class.^name
                ~ " cannot be joined; use preload instead of eager-load";
          }
          my $other-class = $mid-stub.assoc-class-from-spec($mid-stub.belongs-tos{$source});
          my $other-table = Utils.table-name($other-class);
          my $fkey = $source ~ '_id';
          self.joins-values.push: "$kind $other-table ON $other-table.id = $mid-table.$fkey";
          return ($other-class, $other-table);
        }
        if $mid-stub.has-ones{$source}:exists {
          my $other-class = $mid-stub.assoc-class-from-spec($mid-stub.has-ones{$source});
          if $other-class !=== Mu {
            my $other-table = Utils.table-name($other-class);
            my $fkey = $mid-stub.assoc-fkey-from-spec($mid-stub.has-ones{$source}, Utils.to-foreign-key($mid-table));
            self.joins-values.push: "$kind $other-table ON $other-table.$fkey = $mid-table.id";
            return ($other-class, $other-table);
          }
        }
        die "joins: cannot resolve has_one :through '$name' on " ~ $base-class.^name;
      }
      my $other-class = $stub.assoc-class-from-spec($ho);
      if $other-class !=== Mu {
        my $other-table = Utils.table-name($other-class);
        my $fkey = $stub.assoc-fkey-from-spec($ho, Utils.to-foreign-key($base-table));
        self.joins-values.push: "$kind $other-table ON $other-table.$fkey = $base-table.id";
        return ($other-class, $other-table);
      }
    }
    die "joins: unknown association '$name' on " ~ $base-class.^name;
  }
}
