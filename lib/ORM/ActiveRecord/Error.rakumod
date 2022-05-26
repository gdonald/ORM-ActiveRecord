
use ORM::ActiveRecord::Field;

class Error is export {
  has Field $.field;
  has Str $.message;
}
