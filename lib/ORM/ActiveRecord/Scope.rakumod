
use ORM::ActiveRecord::Field;

class Scope is export {
  has $.klass;
  has Str $.name;
  has Block $.block;
}
