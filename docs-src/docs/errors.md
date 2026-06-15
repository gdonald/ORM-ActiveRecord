# Errors

ORM::ActiveRecord exposes two complementary error surfaces:

- **Typed exceptions** for failure modes that callers want to `try { … CATCH { … } }` around — things like a missing row, an invalid record, or an irreversible migration.
- **A per-record `errors` collection** that captures validation failures without throwing, so the caller can inspect every problem on a record at once.

The exceptions live in:

```perl6
use ORM::ActiveRecord::Errors::X;
```

The collection is what `record.errors` returns. It is documented in [The errors collection](#the-errors-collection) at the bottom of this page.

Each exception is a regular Raku `Exception`, so the usual `try { … CATCH { when … } }`
idiom applies. The table below summarises which methods raise which exception;
the sections that follow document the attributes each one carries.

| Exception                  | Raised by                                            |
| -------------------------- | ---------------------------------------------------- |
| `X::RecordNotFound`        | `find`, `find-by-bang`                             |
| `X::RecordInvalid`         | `save-bang`, `update-bang`, `create-bang`      |
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
instead — use `find-by-bang(%conditions)` if you want the loud variant.

## X::RecordInvalid

Raised by the `-bang` persistence methods when validations fail. The
exception carries both the failing record and a list of human-readable
messages built from the model's `errors`.

```perl6
use ORM::ActiveRecord::Errors::X;

try {
  User.create-bang({fname => ''});

  CATCH {
    when X::RecordInvalid {
      say .message;        # Validation failed: fname must be present
      say .messages;       # (fname must be present)
      say .record.fname;   # ''
    }
  }
}
```

`save` / `update` / `create` (without `-bang`) return `False` on validation
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

## The errors collection

Every model instance carries an `errors` object — an instance of
`ORM::ActiveRecord::Errors::Errors` — that validators populate during
`is-valid` / `is-invalid`. The collection mirrors Rails' `ActiveModel::Errors`
API so the same patterns (`add`, `delete`, `clear`, `where`, `details`,
`full-messages`, `is-added`, `group-by-attribute`, `merge`, …) work without
translation.

Each entry is an `ORM::ActiveRecord::Errors::Error` carrying:

| Field      | Meaning                                                              |
| ---------- | -------------------------------------------------------------------- |
| `attribute`| Attribute the error is attached to (`'base'` for record-level errors)|
| `type`     | Short symbolic kind (e.g. `'blank'`, `'taken'`, `'greater-than'`)    |
| `message`  | Human-readable failure message (already interpolated)                |
| `options`  | Hash of options preserved from the `add` call (e.g. `count => 5`)    |

### Adding errors

`add` is the primary way to append an error from user code or from a custom
validator. The second argument is the error *type*; pass `:message` to override
the rendered text, and any extra named options interpolate into the template.

```perl6
$record.errors.add('email', 'blank');                                 # type=blank, message='must be present'
$record.errors.add('email', 'taken', message => 'is already used');   # type=taken, overridden message
$record.errors.add('email', 'must be valid');                         # type=invalid (any whitespace ⇒ literal message)
$record.errors.add('age',   'greater-than', count => 0);              # interpolates {count}
```

When no explicit `message` is given, `add` resolves the template through the
active locale before falling back to the built-in default, and interpolates the
`{model}`, `{attribute}`, `{value}`, and `{count}` tokens (plus any extra option
passed to `add`). See [Messages & locales](validations/i18n.md).

Pre-built `Error` instances (for example, when copying errors from one record
to another) can be appended with `import`:

```perl6
$record.errors.import(Error.new(:$field, :message<imported>, :type<custom>));
```

### Removing errors

```perl6
$record.errors.delete('email');               # remove every error on :email
$record.errors.delete('email', 'taken');      # only the :taken kind on :email
$record.errors.clear;                         # wipe the collection
```

### Reading errors

```perl6
$record.errors.size;             # Int — number of errors
$record.errors.count;            # alias of size
$record.errors.is-any;           # Bool — any errors?
$record.errors.is-empty;         # Bool — no errors?
$record.errors.attribute-names;  # ('email', 'age') — unique attributes with errors

$record.errors.full-messages;             # ('email must be present', 'age must be greater than 0')
$record.errors.full-messages-for('email');# ('email must be present')
$record.errors.messages;                  # { email => ('must be present',) }

$record.errors.details;
# { email => ({error => 'blank'}, ), age => ({error => 'greater-than', count => 0}, ) }

$record.errors.group-by-attribute;
# { email => [Error, Error], age => [Error] }

$record.errors.objects;          # full sequence of Error objects
```

Indexed access (`$record.errors[0]`) and FALLBACK access by attribute name
(`$record.errors.email`) are both supported. The FALLBACK form returns a
sequence of messages for that attribute, so it composes with `[0]` or
stringification: `$record.errors.email[0] eq 'must be present'`.

### Looking for specific errors

```perl6
$record.errors.where(:attribute<email>);            # all errors on email
$record.errors.where(:type<taken>);                 # all 'taken' errors
$record.errors.where(:attribute<email>, :type<blank>);

$record.errors.is-of-kind('email', 'blank');        # Bool — any blank error on email?
$record.errors.is-added('age', 'greater-than', count => 0);  # Bool — exact match incl. options
```

### Merging errors between records

`merge` appends another record's errors onto this one. Useful when bubbling
errors up from an associated record.

```perl6
$parent.errors.merge($child.errors);
```

### Error types emitted by built-in validators

| Validator                  | Type(s) recorded                                        |
| -------------------------- | ------------------------------------------------------- |
| `:presence`                | `blank`                                                 |
| `length` (`max`)           | `too-long` (carries `:count`)                           |
| `length` (`min`)           | `too-short` (carries `:count`)                          |
| `length` (`is` / `in`)     | `wrong-length` (carries `:count` when `is`)             |
| `:acceptance`              | `accepted`                                              |
| `:confirmation`            | `confirmation`                                          |
| `inclusion`                | `inclusion`                                             |
| `exclusion`                | `exclusion`                                             |
| `format`                   | `invalid`                                               |
| `numericality` / `comparison` | `greater-than`, `greater-than-or-equal-to`, `less-than`, `less-than-or-equal-to`, `equal-to`, `other-than` (each carries `:count`) |
| `uniqueness`               | `taken`                                                 |
| `validates-associated`     | `invalid`                                               |
| automatic `belongs-to` presence | `blank`                                            |
| `dependent: :restrict_with_error` | `restrict-dependent-destroy`                     |
