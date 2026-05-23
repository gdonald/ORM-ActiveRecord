# Errors

ORM::ActiveRecord raises typed exceptions for the failure modes that callers
typically want to handle (a missing row, a record that failed validation, a
modification attempt on a `readonly` record, an irreversible migration). All
of them live in one module:

```perl6
use ORM::ActiveRecord::Errors::X;
```

Each exception is a regular Raku `Exception`, so the usual `try { … CATCH { when … } }`
idiom applies. The table below summarises which methods raise which exception;
the sections that follow document the attributes each one carries.

| Exception                  | Raised by                                            |
| -------------------------- | ---------------------------------------------------- |
| `X::RecordNotFound`        | `find`, `find-by-or-die`                             |
| `X::RecordInvalid`         | `save-or-die`, `update-or-die`, `create-or-die`      |
| `X::ReadOnlyRecord`        | `save` / `update` / `destroy` / `delete` on a record from a `readonly` relation |
| `X::IrreversibleMigration` | `self.irreversible-migration` inside a migration `down` |
| `X::StrictValidationFailed`| validator declared with `:strict` — see [Validator Options &raquo; strict](validations/options.md#strict) |

## X::RecordNotFound

Raised when a finder can prove the row does not exist.

```perl6
use ORM::ActiveRecord::Errors::X;

try {
  User.find(0);

  CATCH {
    when X::RecordNotFound {
      say .message;   # Couldn't find User with id=0
      say .model;     # User
      say .id;        # 0
    }
  }
}
```

`find($id)` always raises on a miss. `find-by(%conditions)` returns `Nil`
instead — use `find-by-or-die(%conditions)` if you want the loud variant.

## X::RecordInvalid

Raised by the `-or-die` persistence methods when validations fail. The
exception carries both the failing record and a list of human-readable
messages built from the model's `errors`.

```perl6
use ORM::ActiveRecord::Errors::X;

try {
  User.create-or-die({fname => ''});

  CATCH {
    when X::RecordInvalid {
      say .message;        # Validation failed: fname must be present
      say .messages;       # (fname must be present)
      say .record.fname;   # ''
    }
  }
}
```

`save` / `update` / `create` (without `-or-die`) return `False` on validation
failure instead of raising — inspect `.errors` on the record to see what went
wrong. See [Persistence](models/persistence.md) for the full quiet-vs-loud
breakdown.

## X::ReadOnlyRecord

Raised when any write method (`save`, `update`, `destroy`, `delete`) is
invoked on a record that was fetched through a `readonly` relation.

```perl6
use ORM::ActiveRecord::Errors::X;

my $user = User.readonly.first;

try {
  $user.save;

  CATCH {
    when X::ReadOnlyRecord {
      say .message;   # User is marked as readonly
      say .model;     # User
    }
  }
}
```

Clear the flag with `unscope(:readonly)` on the relation before fetching if
you want a writable record. See [Aggregation &raquo; readonly](models/aggregation.md#readonly).

## X::IrreversibleMigration

Raised from inside a migration `down` to signal that the change can't be
rolled back automatically. The `ar` runner catches it, reports which file
fired, and aborts the rollback.

```perl6
use ORM::ActiveRecord::Schema::Migration;

class DropLegacyAuditLog is Migration {
  method up {
    self.drop-table: 'legacy_audit_log';
  }

  method down {
    self.irreversible-migration;
  }
}
```

`self.irreversible-migration` is a one-liner that constructs and throws the
exception — it exists so the intent reads as a migration step rather than
manual exception plumbing. See [Migrations &raquo; Irreversible migrations](migrations.md#irreversible-migrations).

## X::StrictValidationFailed

Raised from `is-valid` / `is-invalid` when a validator declared with `:strict`
fails — instead of pushing onto `errors`, the chain aborts and this exception
carries the underlying message and the failing attribute name.

```perl6
use ORM::ActiveRecord::Errors::X;

try {
  $event.is-valid;

  CATCH {
    when X::StrictValidationFailed {
      say .model;          # Event
      say .attribute;      # name
      say .message-text;   # must be present
    }
  }
}
```

See [Validator Options &raquo; strict](validations/options.md#strict) for the
declaration syntax.
