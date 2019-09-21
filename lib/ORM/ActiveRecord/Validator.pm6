
use ORM::ActiveRecord::Field;

class Validator is export {
  has $.klass;
  has Field $.field;
  has Hash $.params;
}
