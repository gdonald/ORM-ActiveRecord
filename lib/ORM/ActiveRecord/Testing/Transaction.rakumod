
use ORM::ActiveRecord::DB;

# Transactional test helpers. Wrap each test in a transaction that is rolled
# back at teardown, so the database is left untouched between examples without
# DELETE / TRUNCATE. Nested model transactions join the open one (savepoints),
# so a test's own `transaction { ... }` blocks still behave.
#
#   use ORM::ActiveRecord::Testing::Transaction;
#
#   before-each { begin-transactional-test }
#   after-each  { rollback-transactional-test }
#
# or wrap a single body:
#
#   with-rollback { User.create({ ... }); ... }

sub begin-transactional-test(Str :$isolation) is export {
  DB.shared.adapter.open-transaction(:$isolation);
}

sub rollback-transactional-test is export {
  DB.shared.adapter.force-rollback;
}

sub with-rollback(&block) is export {
  begin-transactional-test;
  LEAVE { rollback-transactional-test }
  block();
}

class TransactionalTests is export {
  method start(Str :$isolation) { begin-transactional-test(:$isolation) }
  method finish                 { rollback-transactional-test }
  method around(&block)         { with-rollback(&block) }
}
