
role ModelCallbacks is export {
  method before-save(Block $block)    { self.before-saves.push: $block }
  method before-update(Block $block)  { self.before-updates.push: $block }
  method before-create(Block $block)  { self.before-creates.push: $block }
  method after-save(Block $block)     { self.after-saves.push: $block }
  method after-update(Block $block)   { self.after-updates.push: $block }
  method after-create(Block $block)   { self.after-creates.push: $block }
  method before-destroy(Block $block) { self.before-destroys.push: $block }
  method after-destroy(Block $block)  { self.after-destroys.push: $block }

  method do-before-destroys { for self.before-destroys { .() } }
  method do-after-destroys  { for self.after-destroys  { .() } }
  method do-before-saves    { for self.before-saves    { .() } }
  method do-before-creates  { for self.before-creates  { .() } }
  method do-before-updates  { for self.before-updates  { .() } }
  method do-after-saves     { for self.after-saves     { .() } }
  method do-after-creates   { for self.after-creates   { .() } }
  method do-after-updates   { for self.after-updates   { .() } }

  method after-commit(Block $block)         { self.after-commits.push: $block }
  method after-rollback(Block $block)       { self.after-rollbacks.push: $block }
  method after-create-commit(Block $block)  { self.after-create-commits.push: $block }
  method after-update-commit(Block $block)  { self.after-update-commits.push: $block }
  method after-destroy-commit(Block $block) { self.after-destroy-commits.push: $block }
  method after-save-commit(Block $block)    { self.after-save-commits.push: $block }

  method run-after-commit(:%kinds) {
    if %kinds<create> {
      for self.after-create-commits { .() }
    } elsif %kinds<update> {
      for self.after-update-commits { .() }
    }
    if %kinds<destroy> {
      for self.after-destroy-commits { .() }
    }
    if %kinds<create> || %kinds<update> {
      for self.after-save-commits { .() }
    }
    for self.after-commits { .() }
  }

  method run-after-rollback(:%kinds) {
    for self.after-rollbacks { .() }
  }
}
