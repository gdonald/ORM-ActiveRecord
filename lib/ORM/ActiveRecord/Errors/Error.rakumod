
use ORM::ActiveRecord::Schema::Field;

class Error is export {
  has Field $.field;
  has Str $.message;
}
