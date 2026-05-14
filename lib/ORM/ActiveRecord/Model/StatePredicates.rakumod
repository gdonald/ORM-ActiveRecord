
role ModelStatePredicates is export {
  method make-readonly {
    self.is-readonly = True;
    self;
  }

  method is-new-record(--> Bool) {
    self.id == 0 && !self.is-destroyed;
  }

  method is-persisted(--> Bool) {
    self.id != 0 && !self.is-destroyed;
  }

  method is-frozen(--> Bool) {
    self.is-destroyed;
  }
}
