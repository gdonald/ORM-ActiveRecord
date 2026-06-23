
# Value object for SQL LIKE predicates in `where`.
#
#   where(title => LikePredicate.contains('foo'))      # title LIKE '%foo%'
#   where(title => LikePredicate.starts-with('foo'))   # title LIKE 'foo%'
#   where(title => LikePredicate.ends-with('foo'))     # title LIKE '%foo'
#   where.not(title => LikePredicate.contains('foo'))  # title NOT LIKE '%foo%'
#
# `%` and `_` in the search value are escaped so they match literally; the
# emitted clause carries `ESCAPE '\'`, which PostgreSQL, MySQL, and SQLite all
# accept. The where key is the column; the predicate carries the pattern, which
# the adapter turns into a LIKE fragment (see SqlBuilders).

my sub escape-like(Str:D $value --> Str) {
  $value.subst('\\', '\\\\', :g).subst('%', '\\%', :g).subst('_', '\\_', :g)
}

class LikePredicate is export {
  has Str $.pattern is required;

  method contains(Str:D $value) {
    self.bless(pattern => '%' ~ escape-like($value) ~ '%');
  }

  method starts-with(Str:D $value) {
    self.bless(pattern => escape-like($value) ~ '%');
  }

  method ends-with(Str:D $value) {
    self.bless(pattern => '%' ~ escape-like($value));
  }
}
