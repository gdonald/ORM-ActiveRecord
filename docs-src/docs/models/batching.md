# Batching

Loading every row of a large table at once is expensive. The batching methods
walk the table in fixed-size chunks, keyed off the primary key, so memory stays
bounded regardless of table size.

All three methods accept a relation: any `where`, `joins`, or other filter you
chain in front of them applies to every batch. They ignore any `order`, `limit`,
or `offset` already on the relation — batching always orders by `id ASC` and
uses the batch size as its `LIMIT`.

## find-each

`find-each(:batch-size = 1000)` returns a lazy sequence of records. Each row is
yielded once, in `id` ASC order. The query runs one batch at a time under the
hood; the caller sees a flat stream of model instances.

```perl6
for User.find-each(:batch-size(500)) -> $u {
  $u.update({last_seen => DateTime.now});
}

# WHERE conditions narrow the iteration set
for User.where({active => True}).find-each -> $u {
  process($u);
}
```

`find-each` on `.none` yields nothing. Passing `batch-size => 0` (or negative)
raises an exception.

## find-in-batches

`find-in-batches(:batch-size = 1000)` yields arrays of records, one array per
batch. Use it when a step works naturally on a slice — bulk emailing, batched
API calls, anything that benefits from amortising fixed overhead across a
group.

```perl6
for User.find-in-batches(:batch-size(1000)) -> @batch {
  send-digest(@batch);
}
```

The final batch is whatever is left over; it may have fewer rows than
`batch-size`. An empty relation produces zero batches.

## in-batches

`in-batches(:of = 1000, :load = False)` yields a relation per batch instead of
materialised records. Each yielded relation is scoped to its slice of `id`s,
so you can chain further operations on it.

```perl6
# Default: yield Query relations
for User.in-batches(:of(500)) -> $rel {
  say $rel.count;
  $rel.pluck('email').map({ ... });
}

# With :load, yield arrays of already-loaded records
for User.in-batches(:of(500), :load) -> @batch {
  process(@batch);
}
```

`:load` is the same shape as `find-in-batches` — convenient when you already
know you want the records and not the relation.

## How batching iterates

All three methods order by `id ASC` and walk forward using `id > cursor`,
where `cursor` is the id of the last row in the previous batch. This is a
keyset scan: each batch is a single index lookup, with no growing `OFFSET`
penalty as you advance through the table.

Because batching owns the `id` column for its cursor, a `where(id: ...)`
condition on the relation is replaced by the cursor's id range. Filter on
other columns (or pre-filter into a CTE) if you need to constrain the id
domain.
