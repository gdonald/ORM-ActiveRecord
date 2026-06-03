
# Value object for JSON / JSONB predicate operators in `where`.
#
#   where(prefs => JsonPredicate.extract('theme').eq('dark'))
#   where(prefs => JsonPredicate.extract('a', 'b').ne('x'))
#   where(prefs => JsonPredicate.contains({ theme => 'dark' }))   # PG @> / MySQL JSON_CONTAINS
#   where(prefs => JsonPredicate.has-key('theme'))                # PG ? (jsonb)
#
# `extract(...).eq/.ne` compares the *text* at the JSON path (the `->>`
# operator), so it works uniformly across PostgreSQL, MySQL, and SQLite.
#
# The where key is the JSON column; the predicate carries the path / operator /
# value. The adapter turns it into dialect-specific SQL (see SqlBuilders).
class JsonPredicate is export {
  has Str  $.kind is required;   # 'extract' | 'contains' | 'has-key'
  has      @.path;
  has Str  $.cmp = '=';
  has      $.value;

  method extract(*@path) {
    self.bless(:kind<extract>, :@path);
  }

  method contains($value) {
    self.bless(:kind<contains>, :$value);
  }

  method has-key(Str:D $value) {
    self.bless(:kind<has-key>, :$value);
  }

  method !with-cmp(Str:D $cmp, $value) {
    JsonPredicate.new(:kind<extract>, :path(@!path), :$cmp, :$value);
  }

  method eq($v) { self!with-cmp('=',  $v) }
  method ne($v) { self!with-cmp('!=', $v) }
}
