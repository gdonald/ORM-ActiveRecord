
# Appends a SQL comment carrying contextual tags (controller, action, job, or
# anything custom) to each query, so slow-query logs and database tooling can
# trace a statement back to the code that issued it. A tag value may be a
# literal or a Callable that is resolved when the comment is built, which is how
# request-scoped values (current controller / action) are injected.
class QueryLogs is export {
  my Bool $enabled = False;
  my @tags;            # list of Pair: name => (Str | Callable)

  method enable  { $enabled = True }
  method disable { $enabled = False }
  method enabled(--> Bool) { $enabled }

  method set-tags(@new)              { @tags = @new.map({ self!as-pair($_) }) }
  method add-tag(Str:D $name, $value) { @tags.push: ($name => $value) }
  method clear-tags                  { @tags = () }
  method tags(--> List)              { @tags.List }

  method !as-pair($tag --> Pair) {
    $tag ~~ Pair ?? $tag !! die 'QueryLogs: a tag must be a Pair (name => value)';
  }

  # Build the trailing comment, resolving Callable values. Returns '' when
  # disabled or when no tag produces a value.
  method comment(--> Str) {
    return '' unless $enabled && @tags;

    my @parts;
    for @tags -> $tag {
      my $value = $tag.value ~~ Callable ?? $tag.value.() !! $tag.value;
      next without $value;
      @parts.push: self!sanitize($tag.key.Str) ~ ':' ~ self!sanitize($value.Str);
    }

    @parts ?? '/*' ~ @parts.join(',') ~ '*/' !! '';
  }

  # Apply the comment to a statement; returns the SQL unchanged when there is
  # no comment to add.
  method annotate(Str:D $sql --> Str) {
    my $comment = self.comment;
    $comment ?? "$sql $comment" !! $sql;
  }

  method !sanitize(Str:D $string --> Str) {
    $string.subst('*/', '', :g).subst(/<[\n\r]>/, ' ', :g);
  }

  method reset { $enabled = False; @tags = (); }
}
