
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Relation::Query;

role ModelRelations is export {
  method where(Hash:D $params = {}) {
    my $class = self;
    Query.new(:$class, :$params);
  }

  method all {
    my $class = self;
    my %params;
    Query.new(:$class, :params(%params));
  }

  method none                                        { self.all.none }
  method order(*@cols, *%kw)                         { self.all.order(|@cols, |%kw) }
  method reorder(*@cols, *%kw)                       { self.all.reorder(|@cols, |%kw) }
  method in-order-of($col, @values)                  { self.all.in-order-of($col, @values) }
  method limit(Int:D $n)                             { self.all.limit($n) }
  method offset(Int:D $n)                            { self.all.offset($n) }
  method select(*@cols)                              { self.all.select(|@cols) }
  method distinct(Bool:D $on = True)                 { self.all.distinct($on) }
  method group(*@cols)                               { self.all.group(|@cols) }
  method regroup(*@cols)                             { self.all.regroup(|@cols) }
  method from($source, Str $alias?)                  { self.all.from($source, $alias) }
  method references(*@names)                         { self.all.references(|@names) }
  method readonly(Bool:D $on = True)                 { self.all.readonly($on) }
  method extending(*@roles)                          { self.all.extending(|@roles) }
  method having(*@parts)                             { self.all.having(|@parts) }
  method joins(*@args, *%kw)                         { self.all.joins(|@args, |%kw) }
  method left-outer-joins(*@args, *%kw)              { self.all.left-outer-joins(|@args, |%kw) }
  method pluck(*@cols)                               { self.all.pluck(|@cols) }
  method ids                                         { self.all.ids }
  method touch-all(*@names)                          { self.all.touch-all(|@names) }
  method pick(*@cols)                                { self.all.pick(|@cols) }
  method merge(Query:D $other)                       { self.all.merge($other) }
  method excluding(*@records)                        { self.all.excluding(|@records) }
  method missing(*@names, *%kw)                      { self.all.missing(|@names, |%kw) }
  method associated(*@names, *%kw)                   { self.all.associated(|@names, |%kw) }
  method find-each(Int:D :$batch-size = 1000)        { self.all.find-each(:$batch-size) }
  method find-in-batches(Int:D :$batch-size = 1000)  { self.all.find-in-batches(:$batch-size) }
  method in-batches(Int:D :$of = 1000, Bool:D :$load = False) { self.all.in-batches(:$of, :$load) }
  method with(*%kw)                                  { self.all.with(|%kw) }
  method with-recursive(*%kw)                        { self.all.with-recursive(|%kw) }
  method annotate(*@comments)                        { self.all.annotate(|@comments) }
  method optimizer-hints(*@hints)                    { self.all.optimizer-hints(|@hints) }
  method transaction(&block, Bool :$requires-new = False, Str :$isolation) {
    DB.shared.transaction(&block, :$requires-new, :$isolation);
  }
  method to-sql(--> Str)        { self.all.to-sql }
  method explain(--> Str)       { self.all.explain }
  method is-any(--> Bool)       { self.all.is-any }
  method is-empty(--> Bool)     { self.all.is-empty }
  method is-none(--> Bool)      { self.all.is-none }
  method is-one(--> Bool)       { self.all.is-one }
  method is-many(--> Bool)      { self.all.is-many }
}
