use ORM::ActiveRecord::Model;

unit module Discard::Models;

our @discard-events is export = [];

class Notice is Model is export {
  submethod BUILD {
    self.soft-deletes;

    self.before-discard:  -> { @discard-events.push('before-discard') };
    self.after-discard:   -> { @discard-events.push('after-discard') };
    self.after-undiscard: -> { @discard-events.push('after-undiscard') };
  }
}

class Locked is Model is export {
  method table-name { 'notices' }

  submethod BUILD {
    self.soft-deletes;

    self.before-discard: -> { False };
  }
}

class Parcel is Model is export {
  submethod BUILD {
    self.soft-deletes(:column<discarded_at>, :default-scope);
  }
}

GLOBAL::<Notice> := Notice;
GLOBAL::<Locked> := Locked;
GLOBAL::<Parcel> := Parcel;
